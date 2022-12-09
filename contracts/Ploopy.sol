// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import '@openzeppelin/contracts/access/Ownable.sol';
import './interfaces/IFlashLoanRecipient.sol';
import './PloopyConstants.sol';

contract Ploopy is IPloopy, PloopyConstants, Ownable, IFlashLoanRecipient {
  constructor() {
    // approve rewardRouter to spend USDC for minting GLP
    USDC.approve(address(REWARD_ROUTER_V2), type(uint256).max);
    // approve GlpDepositor to spend GLP for minting plvGLP
    sGLP.approve(address(GLP_DEPOSITOR), type(uint256).max);
    // approve lPLVGLP to spend plvGLP to mint lPLVGLP
    PLVGLP.approve(address(lPLVGLP), type(uint256).max);
  }

  function loop(uint256 _plvGlpAmount, uint16 _leverage) external {
    if (tx.origin != msg.sender) revert FAILED('!eoa');
    if (_leverage < DIVISOR || _leverage > MAX_LEVERAGE) revert INVALID_LEVERAGE();

    // Transfer plvGLP to this contract so we can mint in 1 go.
    PLVGLP.transferFrom(msg.sender, address(this), _plvGlpAmount);

    uint256 loanAmount = getNotionalLoanAmountIn1e18(
      _plvGlpAmount * PRICE_ORACLE.getPlvGLPPrice(),
      _leverage
    ) / 1e12; //usdc is 6 decimals

    if (USDC.balanceOf(address(BALANCER_VAULT)) < loanAmount) revert FAILED('usdc<loan');

    // check approval to spend USDC (for paying back flashloan).
    // Possibly can omit to save gas as tx will fail with exceed allowance anyway.
    if (USDC.allowance(msg.sender, address(this)) < loanAmount) revert INVALID_APPROVAL();

    IERC20[] memory tokens;
    tokens[0] = USDC;

    uint256[] memory loanAmounts;
    loanAmounts[0] = loanAmount;

    UserData memory userData = UserData({
      user: msg.sender,
      plvGlpAmount: _plvGlpAmount,
      borrowedToken: USDC,
      borrowedAmount: loanAmount
    });

    BALANCER_VAULT.flashLoan(IFlashLoanRecipient(this), tokens, loanAmounts, abi.encode(userData));
  }

  function receiveFlashLoan(
    IERC20[] memory tokens,
    uint256[] memory amounts,
    uint256[] memory feeAmounts,
    bytes memory userData
  ) external override {
    if (msg.sender != address(BALANCER_VAULT)) revert UNAUTHORIZED('!vault');

    // additional checks?

    UserData memory data = abi.decode(userData, (UserData));
    if (data.borrowedAmount != amounts[0] || data.borrowedToken != tokens[0]) revert FAILED('!chk');

    // sanity check: flashloan has no fees
    if (feeAmounts[0] > 0) revert FAILED('fee>0');

    // mint GLP. Approval needed.
    uint256 glpAmount = REWARD_ROUTER_V2.mintAndStakeGlp(
      address(data.borrowedToken),
      data.borrowedAmount,
      0,
      0
    );
    if (glpAmount == 0) revert FAILED('glp=0');

    // TODO whitelist this contract for plvGLP mint
    // mint plvGLP. Approval needed.
    uint256 _oldPlvglpBal = PLVGLP.balanceOf(address(this));
    GLP_DEPOSITOR.deposit(glpAmount);

    // mint lPLVGLP by depositing plvGLP. Approval needed.
    unchecked {
      uint256 mintedFromBorrow = lPLVGLP.mint(PLVGLP.balanceOf(address(this)) - _oldPlvglpBal);
      //TODO: store the amount minted from borrow, so we can potentially unwind this without fees

      uint256 mintedFromUser = lPLVGLP.mint(data.plvGlpAmount);

      // transfer lPLVGLP minted to user
      lPLVGLP.transfer(data.user, mintedFromBorrow + mintedFromUser);
    }

    // call borrowBehalf to borrow USDC on behalf of user
    lUSDC.borrowBehalf(data.borrowedAmount, data.user);

    // repay loan: msg.sender = vault
    USDC.transferFrom(data.user, msg.sender, data.borrowedAmount);
  }

  function getNotionalLoanAmountIn1e18(
    uint256 _notionalGlpAmountIn1e18,
    uint16 _leverage
  ) private pure returns (uint256) {
    unchecked {
      return ((_leverage - DIVISOR) * _notionalGlpAmountIn1e18) / DIVISOR;
    }
  }
}
