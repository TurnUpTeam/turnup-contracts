// SPDX-License-Identifier: MIT

// for security it is better to lock the version
pragma solidity 0.8.19;

import {TurnupSharesV4Pausable} from "./TurnupSharesV4Pausable.sol";

//import "hardhat/console.sol";

contract TurnupSharesV5 is TurnupSharesV4Pausable {
  error InvalidLength();
  error ContractIsActive();

  modifier onlyWhenPaused() {
    if (!paused) revert ContractIsActive();
    _;
  }

  function unpause() external override onlyOwner {
    // Version 5 is not pausable
    // this is a no-op
  }

  function freeze() external override onlyOwner {
    // Version 5 is not freezable
    // this is a no-op
  }

  function prefillSharesBalances(
    address[] calldata sharesSubjects,
    address[] calldata users,
    uint256[] calldata amounts
  ) external onlyOwner onlyWhenPaused {
    if (sharesSubjects.length != users.length || sharesSubjects.length != amounts.length) revert InvalidLength();
    for (uint256 i = 0; i < sharesSubjects.length; i++) {
      sharesBalance[sharesSubjects[i]][users[i]] = amounts[i];
    }
  }

  function prefillSharesSupply(
    address[] calldata sharesSubjects,
    uint256[] calldata amounts
  ) external onlyOwner onlyWhenPaused {
    if (sharesSubjects.length != amounts.length) revert InvalidLength();
    for (uint256 i = 0; i < sharesSubjects.length; i++) {
      sharesSupply[sharesSubjects[i]] = amounts[i];
    }
  }

  function prefillAuthorizedWishes(
    address[] calldata sharesSubjects,
    address[] calldata wishes
  ) external onlyOwner onlyWhenPaused {
    if (sharesSubjects.length != wishes.length) revert InvalidLength();
    for (uint256 i = 0; i < sharesSubjects.length; i++) {
      authorizedWishes[sharesSubjects[i]] = wishes[i];
    }
  }

  function prefillWishPass(
    address wisher,
    address owner,
    uint256 totalSupply,
    uint256 createdAt,
    address subject,
    bool isClaimReward,
    uint256 reservedQuantity,
    uint256 subjectReward,
    uint256 parkedFees
  ) external onlyOwner onlyWhenPaused {
    wishPasses[wisher].owner = owner;
    wishPasses[wisher].totalSupply = totalSupply;
    wishPasses[wisher].createdAt = createdAt;
    wishPasses[wisher].subject = subject;
    wishPasses[wisher].isClaimReward = isClaimReward;
    wishPasses[wisher].reservedQuantity = reservedQuantity;
    wishPasses[wisher].subjectReward = subjectReward;
    wishPasses[wisher].parkedFees = parkedFees;
  }

  function prefillWishPassBalances(
    address wisher,
    address[] calldata users,
    uint256[] calldata balances
  ) external onlyOwner onlyWhenPaused {
    if (users.length != balances.length) revert InvalidLength();
    for (uint256 i = 0; i < balances.length; i++) {
      wishPasses[wisher].balanceOf[users[i]] = balances[i];
    }
  }

  // @dev This empty reserved space is put in place to allow future versions to add new
  // variables without shifting down storage in the inheritance chain.
  // See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps

  uint256[50] private __gap;
}
