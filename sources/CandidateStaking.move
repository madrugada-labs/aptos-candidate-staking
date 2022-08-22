module CandidateStaking::Stakings {

    use std::signer;
    // use std::vector;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin;
    use aptos_framework::account;
    use aptos_framework::coins;

    // Errors
    const EJOB_ALREADY_EXISTS: u64 = 0;
    const EADMIN_ALREADY_EXISTS: u64 = 1;
    const EADMIN_NOT_CREATED: u64 = 2;
    const EJOB_NOT_CREATED: u64 = 3;
    const EAPPLICATION_ALREADY_EXISTS: u64 = 4;
    const EAPPLICATION_NOT_CREATED: u64 = 5;
    const ETRANSFER_FAILED: u64 = 6;
    const EACCOUNT_ALREADY_EXISTS: u64 = 7;
    const EINVALID_BALANCE: u64 = 8;
    const EINVALID_STATUS: u64 = 9;
    const ESTATUS_STILL_PENDING: u64 = 10;
    const ESELECTED_BUT_CANT_TRANSFER: u64 = 11;
    const ENOT_STAKED_YET: u64 = 12;
    const ECANNOT_UNSTAKE_AGAIN: u64 = 13;

    // Application States
    const PENDING: u8 = 0;
    const SELECTED: u8 = 1;
    const REJECTED: u8 = 2;
    const SELECTED_BUT_CANT_TRANSFER: u8 = 3;

    struct Job has key, store, drop {
        total_reward_to_be_given: u64,
        resource: address,
        resource_cap: account::SignerCapability
    }

    struct Application has key, store, drop {
        status: u8,
        staked_amount: u64,
        max_allowed_stake: u64,
        total_reward_amount: u64,
        update_reward_value_in_job: bool
    }

    struct StakeInfo has key, store, drop {
        staked_amount: u64,
        reward_amount: u64
    }

    struct Admin has key {
        authority: address
    }

    public entry fun init_admin(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        assert!(!exists<Admin>(admin_addr), EADMIN_ALREADY_EXISTS);
        move_to<Admin>(admin, Admin{authority: admin_addr});
    }

    public entry fun init_job(recruiter: &signer, job_id: vector<u8>) {
        let recruiter_addr = signer::address_of(recruiter);
        assert!(!exists<Job>(recruiter_addr), 1);
        let (escrow, escrow_signer_cap) = account::create_resource_account(recruiter, job_id);
        let escrow_addr = signer::address_of(&escrow);
        coins::register<aptos_coin::AptosCoin>(&escrow);
        move_to<Job>(recruiter, Job{total_reward_to_be_given: 0, resource: escrow_addr, resource_cap: escrow_signer_cap});
    }

    public entry fun init_application(applicant: &signer, _application_id: vector<u8>, max_allowed_stake: u64) {
       let applicant_addr = signer::address_of(applicant);
       assert!(!exists<Application>(applicant_addr), EAPPLICATION_ALREADY_EXISTS);
       move_to<Application>(applicant, Application{status: PENDING, staked_amount: 0, max_allowed_stake: max_allowed_stake, total_reward_amount: 0, update_reward_value_in_job: false});
    }

    public entry fun stake(staker: &signer,recruiter: address, applicant: address, amount: u64) acquires Job, Application, StakeInfo {  

        assert!(exists<Job>(recruiter), EJOB_NOT_CREATED);
        assert!(exists<Application>(applicant), EAPPLICATION_NOT_CREATED);
        let staker_addr = signer::address_of(staker);
        let job_info = borrow_global<Job>(recruiter);
        let application_info = borrow_global_mut<Application>(applicant);
        let balanceBefore = coin::balance<aptos_coin::AptosCoin>(staker_addr);
        coin::transfer<aptos_coin::AptosCoin>(staker, job_info.resource, amount);
        let balanceAfter = coin::balance<aptos_coin::AptosCoin>(staker_addr);
        assert!((balanceBefore - balanceAfter) == amount, ETRANSFER_FAILED);
        application_info.staked_amount = application_info.staked_amount + amount;  
        if (!exists<StakeInfo>(staker_addr)) {
            let reward_amount = 3 * amount;
            move_to(staker, StakeInfo{staked_amount: amount, reward_amount: reward_amount}); 
            application_info.total_reward_amount = application_info.total_reward_amount + reward_amount;
        } else {
            let stake_info = borrow_global_mut<StakeInfo>(staker_addr);
            stake_info.staked_amount = stake_info.staked_amount + amount;
            stake_info.reward_amount = 3 * stake_info.staked_amount;
        };
    }

    public entry fun change_application_state(admin: &signer, recruiter: address, applicant: address, status: u8) acquires Job, Application {
        assert!(exists<Job>(recruiter), EJOB_NOT_CREATED);
        assert!(exists<Application>(applicant), EAPPLICATION_NOT_CREATED);
        assert!(exists<Admin>(signer::address_of(admin)), EADMIN_NOT_CREATED);
        
        let application_info = borrow_global_mut<Application>(applicant);
        assert!(status < 5, EINVALID_STATUS);
        application_info.status = status;

        if (status == SELECTED_BUT_CANT_TRANSFER || status == SELECTED) {
            let job_info = borrow_global_mut<Job>(recruiter);
            job_info.total_reward_to_be_given = job_info.total_reward_to_be_given + application_info.total_reward_amount;
        }
    }

    public entry fun unstake(staker: &signer, recruiter: address, applicant: address) acquires Job, Application, StakeInfo {
        let staker_addr = signer::address_of(staker); 

        assert!(exists<Job>(recruiter), EJOB_NOT_CREATED);
        assert!(exists<Application>(applicant), EAPPLICATION_NOT_CREATED);
        assert!(exists<StakeInfo>(staker_addr), ENOT_STAKED_YET);

        let application_info = borrow_global<Application>(applicant);
        let job_info = borrow_global<Job>(recruiter);
        let stake_info = borrow_global_mut<StakeInfo>(staker_addr);

        assert!(stake_info.staked_amount != 0, ECANNOT_UNSTAKE_AGAIN); 
        assert!(application_info.status != PENDING, ESTATUS_STILL_PENDING);
        assert!(application_info.status != SELECTED_BUT_CANT_TRANSFER, ESELECTED_BUT_CANT_TRANSFER);

        let resource_account_from_cap = account::create_signer_with_capability(&job_info.resource_cap);

        if (application_info.status == SELECTED) {
            let balanceBefore = coin::balance<aptos_coin::AptosCoin>(staker_addr);
            coin::transfer<aptos_coin::AptosCoin>(&resource_account_from_cap,staker_addr, stake_info.reward_amount);
            let balanceAfter = coin::balance<aptos_coin::AptosCoin>(staker_addr);
            assert!((balanceAfter - balanceBefore) == stake_info.reward_amount, ETRANSFER_FAILED);
        } else if (application_info.status == REJECTED) {
            let balanceBefore = coin::balance<aptos_coin::AptosCoin>(staker_addr);
            coin::transfer<aptos_coin::AptosCoin>(&resource_account_from_cap,staker_addr, stake_info.staked_amount);
            let balanceAfter = coin::balance<aptos_coin::AptosCoin>(staker_addr);
            assert!((balanceAfter - balanceBefore) == stake_info.staked_amount, ETRANSFER_FAILED);
        };

        stake_info.staked_amount = 0;
        stake_info.reward_amount = 0;
    }

    #[test_only]
    struct TestMoneyCapabilities has key {
        mint_cap: coin::MintCapability<aptos_coin::AptosCoin>,
        burn_cap: coin::BurnCapability<aptos_coin::AptosCoin>,
    }

    #[test(admin = @0x4, recruiter = @0x2, applicant = @0x3, staker = @0x1, faucet = @CoreResources)]
    public entry fun can_init_admin(admin: signer, recruiter: signer, applicant: signer, staker: signer, faucet: signer) acquires Job, Application, StakeInfo {
        init_admin(&admin);
        let admin_addr = signer::address_of(&admin);
        assert!(exists<Admin>(admin_addr), EADMIN_NOT_CREATED);

        init_job(&recruiter, b"01");
        let recruiter_addr = signer::address_of(&recruiter);
        assert!(exists<Job>(recruiter_addr), EJOB_NOT_CREATED);

        init_application(&applicant, b"01", 10000);
        let applicant_addr = signer::address_of(&applicant);
        assert!(exists<Application>(applicant_addr), EAPPLICATION_NOT_CREATED);

        let staker_addr = signer::address_of(&staker);
        let faucet_addr = signer::address_of(&faucet);
        assert!(!exists<StakeInfo>(staker_addr), EACCOUNT_ALREADY_EXISTS);
        let (mint_cap, burn_cap) = aptos_coin::initialize(&staker, &faucet);
        move_to(&faucet, TestMoneyCapabilities {
            mint_cap,
            burn_cap
        });
        assert!(coin::balance<aptos_coin::AptosCoin>(faucet_addr) == 18446744073709551615, EINVALID_BALANCE);
        coin::register_for_test<aptos_coin::AptosCoin>(&staker);
        coin::transfer<aptos_coin::AptosCoin>(&faucet, staker_addr, 100);
        stake(&staker, recruiter_addr, applicant_addr, 100);
        assert!(coin::balance<aptos_coin::AptosCoin>(staker_addr) == 0, EINVALID_BALANCE);

        change_application_state(&admin, recruiter_addr, applicant_addr, SELECTED);
        let application_info = borrow_global<Application>(applicant_addr); 
        assert!(application_info.status == SELECTED, EINVALID_STATUS);

        let job_info = borrow_global<Job>(recruiter_addr);
        let resource_address = job_info.resource; 
        coin::transfer<aptos_coin::AptosCoin>(&faucet, resource_address, job_info.total_reward_to_be_given);
        unstake(&staker, recruiter_addr, applicant_addr);
        assert!(coin::balance<aptos_coin::AptosCoin>(staker_addr) == 300, EINVALID_BALANCE);


    }
}