// SPDX-License-Identifier: MIT

// for security it is better to lock the version
pragma solidity 0.8.19;

import {TurnupSharesV4Pausable} from "./TurnupSharesV4Pausable.sol";

//import "hardhat/console.sol";

contract TurnupSharesV5 is TurnupSharesV4Pausable {
  error InvalidLength();
  error ContractIsActive();
  error NotActiveYet();

  bool public isActive;
  TurnupSharesV4Pausable private _source;

  modifier ifActive() virtual override {
    if (!isActive) revert NotActiveYet();
    _;
  }

  modifier ifNotActive() {
    if (isActive) revert ContractIsActive();
    _;
  }

  // solhint-disable-next-line
  receive() external payable {}

  function unpause() external override onlyOwner {
    isActive = true;
  }

  function pause() external override onlyOwner {
    // when active it cannot be paused again
  }

  function freeze() external override onlyOwner {
    // Not freezable
  }

  function setSource(address source_) external onlyOwner {
    _source = TurnupSharesV4Pausable(source_);
  }

  // solhint-disable-next-line
  function importVariables(uint256 DAOBalance_, uint256 protocolFees_) external onlyOwner ifNotActive {
    afterUpgrade();
    DAOBalance = DAOBalance_;
    protocolFees = protocolFees_;
  }

  function importSharesBalances(address[] calldata sharesSubjects, address[] calldata users) external onlyOwner ifNotActive {
    if (sharesSubjects.length != users.length) revert InvalidLength();
    for (uint256 i = 0; i < sharesSubjects.length; i++) {
      sharesBalance[sharesSubjects[i]][users[i]] = _source.sharesBalance(sharesSubjects[i], users[i]);
    }
  }

  function importSharesSupply(address[] calldata sharesSubjects) external onlyOwner ifNotActive {
    for (uint256 i = 0; i < sharesSubjects.length; i++) {
      sharesSupply[sharesSubjects[i]] = _source.sharesSupply(sharesSubjects[i]);
    }
  }

  function importAuthorizedWishes(address[] calldata sharesSubjects) external onlyOwner ifNotActive {
    for (uint256 i = 0; i < sharesSubjects.length; i++) {
      authorizedWishes[sharesSubjects[i]] = _source.authorizedWishes(sharesSubjects[i]);
    }
  }

  function importWishPass(address wisher) external onlyOwner ifNotActive {
    (
      address owner,
      uint256 totalSupply,
      uint256 createdAt,
      address subject,
      bool isClaimReward,
      uint256 reservedQuantity,
      uint256 subjectReward,
      uint256 parkedFees
    ) = _source.wishPasses(wisher);
    wishPasses[wisher].owner = owner;
    wishPasses[wisher].totalSupply = totalSupply;
    wishPasses[wisher].createdAt = createdAt;
    wishPasses[wisher].subject = subject;
    wishPasses[wisher].isClaimReward = isClaimReward;
    wishPasses[wisher].reservedQuantity = reservedQuantity;
    wishPasses[wisher].subjectReward = subjectReward;
    wishPasses[wisher].parkedFees = parkedFees;
  }

  function importWishPassBalances(address wisher, address[] calldata users) external onlyOwner ifNotActive {
    for (uint256 i = 0; i < users.length; i++) {
      wishPasses[wisher].balanceOf[users[i]] = _source.getWishPassBalance(wisher, users[i]);
    }
  }

  // @dev This empty reserved space is put in place to allow future versions to add new
  // variables without shifting down storage in the inheritance chain.
  // See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps

  uint256[50] private __gap;
}
