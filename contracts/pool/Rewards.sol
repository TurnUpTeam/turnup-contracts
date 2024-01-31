// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Import Ownable2Step from OpenZeppelin
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
// Import SafeERC20

import {ICorePool} from "./ICorePool.sol";

//import {console} from "hardhat/console.sol";

abstract contract Rewards is ICorePool, Ownable2StepUpgradeable, PausableUpgradeable {
  error InitBlockNotSet();

  uint256 internal _weightMultiplier;
  uint256 internal _rewardPerWeightMultiplier;

  RewardsConfig internal _config;

  function getConfig() external view returns (RewardsConfig memory) {
    return _config;
  }

  // solhint-disable-next-line func-name-mixedcase
  function __Rewards_init(uint256 _initBlock, uint256 _minLockTime, uint256 _totalReserved) internal onlyInitializing {
    __Ownable_init();
    __Pausable_init();
    if (_initBlock == 0 || _initBlock < block.number) revert InitBlockNotSet();
    _weightMultiplier = 1e6;
    _rewardPerWeightMultiplier = 2e20;
    // preset for Polygon PoS
    _config = RewardsConfig({
      tokensPerBlock: _totalReserved / 2e10,
      // one week
      blocksPerUpdate: 42000 * 7,
      initBlock: _initBlock,
      // two years
      endBlock: _initBlock + 42000 * 365 * 2,
      minLockTime: _minLockTime,
      totalReserved: _totalReserved,
      totalYieldRewards: 0,
      yieldRewardsPerWeight: 0,
      decayFactor: 97,
      lastRatioUpdate: _initBlock,
      usersLockingWeight: 0,
      lastYieldDistribution: _initBlock
    });
  }

  function usersLockingWeight() external view returns (uint256) {
    return _config.usersLockingWeight;
  }

  function shouldUpdateRatio() public view returns (bool) {
    // if yield farming period has ended
    if (blockNumber() > _config.endBlock && _config.lastRatioUpdate == _config.endBlock) {
      // TOKEN/block reward cannot be updated anymore
      return false;
    }

    // check if blocks/update (91252 blocks) have passed since last update
    return blockNumber() >= _config.lastRatioUpdate + _config.blocksPerUpdate;
  }

  error TooFrequent();

  function updateTokenPerBlock() public whenNotPaused {
    // checks if ratio can be updated i.e. if blocks/update (91252 blocks) have passed
    if (!shouldUpdateRatio()) revert TooFrequent();

    uint256 currentBlock = blockNumber() > _config.endBlock ? _config.endBlock : blockNumber();

    // in production it should happen many times per block, but in test, we jump to
    // new blocks, so, this make the function working also in test, and if something weird
    // happens and nobody triggers the function for more than a block, it still works correctly
    uint256 numberOfPeriods = (currentBlock - _config.lastRatioUpdate) / _config.blocksPerUpdate;
    uint256 newTokenPerBlock = _config.tokensPerBlock;
    for (uint256 i = 0; i < numberOfPeriods; i++) {
      newTokenPerBlock = (newTokenPerBlock * _config.decayFactor) / 100;
    }
    _config.tokensPerBlock = newTokenPerBlock;
    _config.lastRatioUpdate = currentBlock;

    // emit an event
    emit TokenRatioUpdated(_config.tokensPerBlock);
  }

  function _pendingYieldRewards(uint256 _usersLockingWeight) internal view returns (uint256) {
    return weightToReward(_usersLockingWeight, _config.yieldRewardsPerWeight);
  }

  /**
   * @dev Testing time-dependent functionality is difficult and the best way of
   *      doing it is to  block number in helper test smart contracts
   *
   * @return `block.number` in mainnet, custom values in testnets (if overridden)
   */
  function blockNumber() public view virtual returns (uint256) {
    // return current block number
    return block.number;
  }

  /**
   * @dev Testing time-dependent functionality is difficult and the best way of
   *      doing it is to  time in helper test smart contracts
   *
   * @return `block.timestamp` in mainnet, custom values in testnets (if overridden)
   */
  function now256() public view virtual returns (uint256) {
    // return current block timestamp
    return block.timestamp;
  }

  function getStakeWeight(uint256 lockedTime, uint256 stakedAmount) public view returns (uint256) {
    return ((lockedTime * _weightMultiplier) / 365 days + _weightMultiplier) * stakedAmount;
  }

  function weightToReward(uint256 _weight, uint256 rewardPerWeight) public view returns (uint256) {
    // apply the formula and return
    return (_weight * rewardPerWeight) / _rewardPerWeightMultiplier;
  }

  function rewardToWeight(uint256 reward, uint256 rewardPerWeight) public view returns (uint256) {
    // apply the reverse formula and return
    return (reward * _rewardPerWeightMultiplier) / rewardPerWeight;
  }

  function _sync() internal virtual {
    // update TOKEN per block value in factory if required
    if (shouldUpdateRatio()) {
      updateTokenPerBlock();
    }
    // check bound conditions and if these are not met -
    // exit silently, without emitting an event
    if (_config.endBlock < _config.lastYieldDistribution) {
      return;
    }
    if (_config.lastYieldDistribution > blockNumber()) {
      return;
    }
    // if locking weight is zero - update only `lastYieldDistribution` and exit
    if (_config.usersLockingWeight == 0) {
      _config.lastYieldDistribution = blockNumber();
      return;
    }
    // to calculate the reward we need to know how many blocks passed, and reward per block
    uint256 currentBlock = blockNumber() > _config.endBlock ? _config.endBlock : blockNumber();
    uint256 blocksPassed = currentBlock - _config.lastYieldDistribution;

    // calculate the reward
    uint256 rewards = blocksPassed * _config.tokensPerBlock;

    _config.totalYieldRewards += rewards;

    // update rewards per weight and `lastYieldDistribution`
    _config.yieldRewardsPerWeight += rewardToWeight(rewards, _config.usersLockingWeight);
    _config.lastYieldDistribution = currentBlock;

    // emit an event
    emit Synchronized(_config.yieldRewardsPerWeight, _config.lastYieldDistribution);
  }

  function pause() external onlyOwner {
    _pause();
  }

  function unpause() external onlyOwner {
    _unpause();
  }

  uint256[50] private __gap;
}
