// SPDX-License-Identifier: MIT

// for security it is better to lock the version
pragma solidity 0.8.19;

import {TurnupSharesV4} from "./TurnupSharesV4.sol";

//import "hardhat/console.sol";

contract TurnupSharesV4c is TurnupSharesV4 {
  event StakeSubject(address indexed sharesSubject, uint32 amount, uint32 lockedFrom, uint32 lockTime);
  error InvalidLockTime();
  error StakingNotActiveYet();

  struct Stake {
    uint32 amount;
    uint32 lockedFrom;
    uint32 lockedUntil;
  }

  mapping(address => Stake[]) public stakes;
  address public rewardsPool;

  modifier onlyRewardsPool() {
    if (rewardsPool == address(0) || _msgSender() != rewardsPool) revert Forbidden();
    _;
  }

  function getVer() public pure virtual override returns (string memory) {
    return "v4.5.0";
  }

  function getNumberOfStakes(address sharesSubject) external view returns (uint256) {
    return stakes[sharesSubject].length;
  }

  function getStakeByIndex(address sharesSubject, uint256 index) external view returns (uint32, uint32, uint32) {
    Stake storage stake = stakes[sharesSubject][index];
    return (stake.amount, stake.lockedFrom, stake.lockedUntil);
  }

  function _sellKey(address sharesSubject, uint256 supply, uint256 amount, uint256 price) internal virtual override {
    if (sharesSubject == _msgSender()) {
      uint256 availableBalance = nonStakedBalance(sharesSubject);
      if (amount > availableBalance) {
        revert InsufficientKeys(availableBalance);
      }
    }
    super._sellKey(sharesSubject, supply, amount, price);
  }

  function nonStakedBalance(address sharesSubject) public view returns (uint256) {
    uint256 stakedBalance;
    for (uint256 i = 0; i < stakes[sharesSubject].length; i++) {
      Stake storage stake = stakes[sharesSubject][i];
      if (stake.lockedUntil > block.timestamp) {
        stakedBalance += stake.amount;
      }
    }
    return sharesBalance[sharesSubject][sharesSubject] - stakedBalance;
  }

  function stakeSubject(uint32 amount, uint32 lockTime) external {
    if (amount == 0) revert InvalidAmount();
    if (lockTime < 1 weeks) revert InvalidLockTime();
    if (rewardsPool == address(0)) revert StakingNotActiveYet();
    address sharesSubject = _msgSender();
    uint256 availableBalance = nonStakedBalance(sharesSubject);
    if (amount > availableBalance) revert InsufficientKeys(availableBalance);
    uint32 lockedFrom = uint32(block.timestamp);
    uint32 lockedUntil = lockedFrom + lockTime;
    stakes[sharesSubject].push(Stake(amount, lockedFrom, lockedUntil));
    emit StakeSubject(sharesSubject, amount, lockedFrom, lockedUntil);
  }

  function setRewardsPool(address rewardsPool_) public onlyDAO {
    rewardsPool = rewardsPool_;
  }

  // must be called by rewardsPool
  function claimRewards(address sharesSubject) external virtual onlyRewardsPool returns (uint256) {
    uint256 rewards;
    uint256 i;
    while (i < stakes[sharesSubject].length) {
      Stake storage stake = stakes[sharesSubject][i];
      if (stake.lockedUntil < block.timestamp) {
        rewards += stake.amount * (stake.lockedUntil - stake.lockedFrom);
        stakes[sharesSubject][i] = stakes[sharesSubject][stakes[sharesSubject].length - 1];
        stakes[sharesSubject].pop();
      } else {
        i++;
      }
    }
    return rewards;
  }

  // @dev This empty reserved space is put in place to allow future versions to add new
  // variables without shifting down storage in the inheritance chain.
  // See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps

  uint256[50] private __gap;
}
