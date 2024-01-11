// SPDX-License-Identifier: MIT

// for security it is better to lock the version
pragma solidity 0.8.19;

import {TurnupSharesV4} from "./TurnupSharesV4.sol";

//import "hardhat/console.sol";

contract TurnupSharesV4Pausable is TurnupSharesV4 {
  error PausedOrFrozen();

  bool public paused;
  bool public frozen;

  modifier ifActive() {
    if (paused || frozen) revert PausedOrFrozen();
    _;
  }

  function pause() external virtual onlyOwner {
    paused = true;
  }

  function unpause() external virtual onlyOwner {
    paused = false;
  }

  function freeze() external virtual onlyOwner {
    frozen = true;
  }

  function buyShares(address sharesSubject, uint256 amount) public payable virtual override onlyIfSetup nonReentrant ifActive {
    super.buyShares(sharesSubject, amount);
  }

  function sellShares(address sharesSubject, uint256 amount) public virtual override onlyIfSetup nonReentrant ifActive {
    super.sellShares(sharesSubject, amount);
  }

  function batchBuyShares(
    address[] calldata sharesSubjects,
    uint256[] calldata amounts,
    uint256[] calldata expectedPrices
  ) public payable virtual override nonReentrant ifActive {
    super.batchBuyShares(sharesSubjects, amounts, expectedPrices);
  }

  function newWishPass(address wisher, uint256 reservedQuantity) public virtual override onlyOperator ifActive {
    super.newWishPass(wisher, reservedQuantity);
  }

  function bindWishPass(address sharesSubject, address wisher) public virtual override onlyOperator nonReentrant ifActive {
    super.bindWishPass(sharesSubject, wisher);
  }

  function claimReservedWishPass() public payable virtual override nonReentrant ifActive {
    super.claimReservedWishPass();
  }

  function closeExpiredWish(address sharesSubject) public override onlyDAO ifActive {
    super.closeExpiredWish(sharesSubject);
  }

  function withdrawContractBalance(uint256 amount, address beneficiary) public onlyDAO nonReentrant {
    uint256 balance = address(this).balance;
    if (amount == 0) {
      amount = balance;
    }
    (bool success, ) = beneficiary.call{value: amount}("");
    if (!success) revert UnableToSendFunds();
  }

  // @dev This empty reserved space is put in place to allow future versions to add new
  // variables without shifting down storage in the inheritance chain.
  // See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps

  uint256[50] private __gap;
}
