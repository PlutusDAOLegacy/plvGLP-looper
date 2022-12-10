// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import '@openzeppelin/contracts/access/Ownable2Step.sol';
import { IRegistry } from './interfaces/Interfaces.sol';

contract LodestarExemptionsTracker is IRegistry, Ownable2Step {
  mapping(address => uint256) public exemptPlvGlp;
  mapping(address => bool) public isHandler;
  uint256 public tvl;

  function increment(address _user, uint256 _amount) external validateHandler {
    unchecked {
      exemptPlvGlp[_user] += _amount;
      tvl += _amount;
      emit Incremented(_user, _amount);
    }
  }

  function decrement(
    address _user,
    uint256 _amount
  ) external validateHandler returns (uint256 _decrementedAmount) {
    uint256 _oldBorrow = exemptPlvGlp[_user];
    unchecked {
      if (_oldBorrow > _amount) {
        exemptPlvGlp[_user] -= _amount;
        _decrementedAmount = _amount;
      } else {
        exemptPlvGlp[_user] = 0;
        _decrementedAmount = _oldBorrow;
      }

      tvl -= _decrementedAmount;
      emit Decremented(_user, _decrementedAmount);
    }
  }

  modifier validateHandler() {
    if (isHandler[msg.sender] != true) revert UNAUTHORIZED();
    _;
  }

  function setHandler(address _handler, bool _status) external onlyOwner {
    isHandler[_handler] = _status;
    emit HandlerUpdated(_handler, _status);
  }
}
