# Ploopy Description

## As a user:

- deposit plvGLP
- 1 click loop using USDC up to 1 < desired leverage amount < 3

## Contract description

1. start with `x` plvGLP, with desired leverage amount `y` where `10000 < y <= 30000`
2. Flashloan `z` USDC, where `z = (y - 10000) * x` from balancerV2 vault
3. mint plvGLP using USDC
4. mint lPLVGLP using plvGLP through lodestar
5. transfer lPLVGLP to user
6. call `lUSDC.borrowFor` to borrow `z` USDC
7. transfer `z` USDC from user to balancer vault, paying back flashloan

### Approvals

User needs to action 2 approvals:

1. Approve Ploopy to spend at lesat `_plvGlpAmount` plvGLP, for looping
2. Approve Ploopy to spend at least `z` USDC, to repay flash loan
