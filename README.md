# aptos-candidate-staking
This is a smart contract written in move on aptos chain where user can stake on a particular applicant and get rewarded if the applicant is hired.

This is a very rough module written using move. But this module achieves the following things
- Create an admin account which can happen only during the lifetime of the module
- Create a new job and store details related to it in a resource account
- Create a new application and store details related to it in a resource account
- User can stake 
- User can unstake and would get rewards if the candidate gets selected.

Resource accounts are random accounts which are generated using a source address and a seed and has its authorization key rotated to the program. This makes the program in control of the account. This type of account is ideal in storing coins or tokens and can act as an liquidity pool.
