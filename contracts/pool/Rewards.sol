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

  RewardsConfig internal _config;

  uint256 public tokensPerBlock;
  uint256 public totalYieldRewards;
  uint256 public yieldRewardsPerWeight;
  uint256 public lastRatioUpdate;
  uint256 public usersLockingWeight;
  uint256 public lastYieldDistribution;

  function getConfig() external view returns (RewardsConfig memory) {
    return _config;
  }

  // solhint-disable-next-line func-name-mixedcase
  function __Rewards_init(uint256 _initBlock, uint256 _minLockTime, uint256 _totalReserved) internal onlyInitializing {
    __Ownable_init();
    __Pausable_init();
    if (_initBlock == 0 || _initBlock < block.number) revert InitBlockNotSet();

    // preset for Polygon PoS
    tokensPerBlock = _totalReserved / 95e5; // conservatively, leaves around 50M tokens in the pool at the end of the farming period
    lastRatioUpdate = _initBlock;
    lastYieldDistribution = _initBlock;

    _config = RewardsConfig({
      // one week
      blocksPerUpdate: 42000 * 7,
      initBlock: _initBlock,
      // two years
      endBlock: _initBlock + 42000 * 365 * 2,
      minLockTime: _minLockTime,
      totalReserved: _totalReserved,
      decayFactor: 97,
      weightMultiplier: 1e6,
      rewardPerWeightMultiplier: 2e20
    });
  }

  function getCurrentValues() external view returns (uint256, uint256, uint256, uint256, uint256, uint256) {
    return (
      tokensPerBlock,
      totalYieldRewards,
      yieldRewardsPerWeight,
      lastRatioUpdate,
      usersLockingWeight,
      lastYieldDistribution
    );
  }

  function shouldUpdateRatio() public view returns (bool) {
    // if yield farming period has ended
    if (blockNumber() > _config.endBlock && lastRatioUpdate == _config.endBlock) {
      // TOKEN/block reward cannot be updated anymore
      return false;
    }

    // check if blocks/update (91252 blocks) have passed since last update
    return blockNumber() >= lastRatioUpdate + _config.blocksPerUpdate;
  }

  error TooFrequent();

  function updateTokenPerBlock() public whenNotPaused {
    // checks if ratio can be updated i.e. if blocks/update (91252 blocks) have passed
    if (!shouldUpdateRatio()) revert TooFrequent();

    uint256 currentBlock = blockNumber() > _config.endBlock ? _config.endBlock : blockNumber();

    // in production it should happen many times per block, but in test, we jump to
    // new blocks, so, this make the function working also in test, and if something weird
    // happens and nobody triggers the function for more than a block, it still works correctly
    uint256 numberOfPeriods = (currentBlock - lastRatioUpdate) / _config.blocksPerUpdate;
    uint256 newTokenPerBlock = tokensPerBlock;
    for (uint256 i = 0; i < numberOfPeriods; i++) {
      newTokenPerBlock = (newTokenPerBlock * _config.decayFactor) / 100;
    }
    tokensPerBlock = newTokenPerBlock;
    lastRatioUpdate = currentBlock;

    // emit an event
    emit TokenRatioUpdated(tokensPerBlock);
  }

  //  function _pendingYieldRewards(uint256 _usersLockingWeight) internal view returns (uint256) {
  //    return weightToReward(_usersLockingWeight, yieldRewardsPerWeight);
  //  }
  //
  function _pendingYieldRewards(User memory user) internal view returns (uint256 pending) {
    // and perform the calculation using the values read
    return weightToReward(user.totalWeight, yieldRewardsPerWeight) - user.subYieldRewards;
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
    return ((lockedTime * _config.weightMultiplier) / 365 days + _config.weightMultiplier) * stakedAmount;
  }

  function weightToReward(uint256 _weight, uint256 rewardPerWeight) public view returns (uint256) {
    // apply the formula and return
    return (_weight * rewardPerWeight) / _config.rewardPerWeightMultiplier;
  }

  function rewardToWeight(uint256 reward, uint256 rewardPerWeight) public view returns (uint256) {
    // apply the reverse formula and return
    return (reward * _config.rewardPerWeightMultiplier) / rewardPerWeight;
  }

  function _sync() internal virtual {
    // update TOKEN per block value in factory if required
    if (shouldUpdateRatio()) {
      updateTokenPerBlock();
    }
    // check bound conditions and if these are not met -
    // exit silently, without emitting an event
    if (_config.endBlock < lastYieldDistribution) {
      return;
    }
    if (lastYieldDistribution > blockNumber()) {
      return;
    }
    // if locking weight is zero - update only `lastYieldDistribution` and exit
    if (usersLockingWeight == 0) {
      lastYieldDistribution = blockNumber();
      return;
    }
    // to calculate the reward we need to know how many blocks passed, and reward per block
    uint256 currentBlock = blockNumber() > _config.endBlock ? _config.endBlock : blockNumber();
    uint256 blocksPassed = currentBlock - lastYieldDistribution;

    // calculate the reward
    uint256 rewards = blocksPassed * tokensPerBlock;

    totalYieldRewards += rewards;

    // update rewards per weight and `lastYieldDistribution`
    yieldRewardsPerWeight += rewardToWeight(rewards, usersLockingWeight);
    lastYieldDistribution = currentBlock;

    // emit an event
    emit Synchronized(yieldRewardsPerWeight, lastYieldDistribution);
  }

  function pause() external onlyOwner {
    _pause();
  }

  function unpause() external onlyOwner {
    _unpause();
  }

  uint256[50] private __gap;
}
