// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Import Ownable2Step from OpenZeppelin
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
// Import SafeERC20

import {ICorePool} from "./ICorePool.sol";
import {console} from "hardhat/console.sol";

abstract contract Rewards is ICorePool, Ownable2StepUpgradeable, PausableUpgradeable {


  error InitBlockNotSet();

  uint256 internal constant WEIGHT_MULTIPLIER = 1e6;
  uint256 internal constant REWARD_PER_WEIGHT_MULTIPLIER = 1e20;


  RewardsConfig internal _config;

  function getConfig() external view returns (RewardsConfig memory) {
    return _config;
  }

  function __Rewards_init(uint256 _initBlock, uint256 _minLockTime, uint256 _totalReserved) internal onlyInitializing {
    __Ownable_init();
    __Pausable_init();
    if (_initBlock == 0 || _initBlock < block.number) revert InitBlockNotSet();

    // preset for Polygon PoS
    _config = RewardsConfig({
      // The factor is 9387440, but we prefer to be a bit conservative
      tokensPerBlock: _totalReserved / 95e5,
      // one week
      blocksPerUpdate: 42000 * 7,
      initBlock: _initBlock,
      // two years
      endBlock: _initBlock + 42000 * 365 * 2,
      minLockTime: _minLockTime,
      totalReserved: _totalReserved,
      distributedRewards: 0,
      totalYieldRewards: 0,
      yieldRewardsPerWeight: 0,
      decayFactor: 97,
      lastRatioUpdate: _initBlock,
      usersLockingWeight: 0,
      lastYieldDistribution: _initBlock
    });
  }

  function getStakeWeight(uint256 lockedTime, uint256 stakedAmount) public pure  returns (uint256) {
    return (stakedAmount * lockedTime * WEIGHT_MULTIPLIER) / 365 days;
  }

  function weightToReward(uint256 _weight, uint256 rewardPerWeight) public pure  returns (uint256) {
    // apply the formula and return
    return (_weight * rewardPerWeight) / REWARD_PER_WEIGHT_MULTIPLIER;
  }

  function rewardToWeight(uint256 reward, uint256 rewardPerWeight) public pure  returns (uint256) {
    // apply the reverse formula and return
    return (reward * REWARD_PER_WEIGHT_MULTIPLIER) / rewardPerWeight;
  }

  function shouldUpdateRatio() public view  returns (bool) {
    // if yield farming period has ended
    if (blockNumber() > _config.endBlock && _config.lastRatioUpdate == _config.endBlock) {
        // TOKEN/block reward cannot be updated anymore
        return false;
    }

    // check if blocks/update (91252 blocks) have passed since last update
    return blockNumber() >= _config.lastRatioUpdate + _config.blocksPerUpdate;
  }

  error TooFrequent();

  function updateTokenPerBlock() public  whenNotPaused {
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

  //    function pendingYieldRewards(address _staker) external view  returns (uint256) {
  //        // `newYieldRewardsPerWeight` will store stored or recalculated value for `yieldRewardsPerWeight`
  //        uint256 newYieldRewardsPerWeight;
  //
  //        // if smart contract state was not updated recently, `yieldRewardsPerWeight` value
  //        // is outdated and we need to recalculate it in order to calculate pending rewards correctly
  //        if (blockNumber() > config.lastYieldDistribution && usersLockingWeight != 0) {
  //            uint256 multiplier = blockNumber() > config.endBlock
  //                ? config.endBlock - config.lastYieldDistribution
  //                : blockNumber() - config.lastYieldDistribution;
  //            uint256 rewards = multiplier * config.tokensPerBlock;
  //
  //            // recalculated value for `yieldRewardsPerWeight`
  //            newYieldRewardsPerWeight = rewardToWeight(rewards, usersLockingWeight) + yieldRewardsPerWeight;
  //        } else {
  //            // if smart contract state is up to date, we don't recalculate
  //            newYieldRewardsPerWeight = yieldRewardsPerWeight;
  //        }
  //
  //        // based on the rewards per weight value, calculate pending rewards;
  //        User storage user = users[_staker];
  //        uint256 pending = weightToReward(user.totalWeight, newYieldRewardsPerWeight) - user.subYieldRewards;
  //        return pending;
  //    }

  function _pendingYieldRewards(uint256 usersLockingWeight) internal view returns (uint256) {
    return weightToReward(usersLockingWeight, _config.yieldRewardsPerWeight);
  }

//  error ZeroAmount();
//  error InvalidLockInternal();

  /**
   * @dev Used internally, mostly by children implementations, see stake()
   *
   * @param _staker an address which stakes tokens and which will receive them back
   * @param _amount amount of tokens to stake
   * @param _lockUntil stake period as unix timestamp; zero means no locking
   */
//  function _stakeData(uint256 amount, uint256 lockTime, uint256 _userTotalWeight) internal view virtual returns (uint256, uint256, uint256) {
//    // stake weight formula rewards for locking
//    uint256 stakeWeight = getStakeWeight(lockTime, amount);
//    uint256 usersLockingWeight = _userTotalWeight + stakeWeight;
//    uint256 userSubYieldRewards = weightToReward(usersLockingWeight, config.yieldRewardsPerWeight);
//    config.usersLockingWeight += stakeWeight;
//    return (stakeWeight, usersLockingWeight, userSubYieldRewards);
//  }

  /**
   * @dev Testing time-dependent functionality is difficult and the best way of
   *      doing it is to  block number in helper test smart contracts
   *
   * @return `block.number` in mainnet, custom values in testnets (if overridden)
   */
  function blockNumber() public view virtual  returns (uint256) {
    // return current block number
    return block.number;
  }

  /**
   * @dev Testing time-dependent functionality is difficult and the best way of
   *      doing it is to  time in helper test smart contracts
   *
   * @return `block.timestamp` in mainnet, custom values in testnets (if overridden)
   */
  function now256() public view virtual  returns (uint256) {
    // return current block timestamp
    return block.timestamp;
  }

//  function _unstakeData(uint256 previousWeight, uint256 lockedTime, uint256 stakedAmount, uint256 amount) internal virtual {
//    // recalculate deposit weight
//    uint256 newWeight = ((lockedTime * WEIGHT_MULTIPLIER) /
//      365 days +
//      WEIGHT_MULTIPLIER) * (stakedAmount - amount);
//
//    // update the deposit, or delete it if its depleted
//    if (stakeDeposit.tokenAmount - _amount == 0) {
//      delete user.deposits[_depositId];
//    } else {
//      stakeDeposit.tokenAmount -= _amount;
//      stakeDeposit.weight = newWeight;
//    }
//
//    // update user record
//    user.tokenAmount -= _amount;
//    user.totalWeight = user.totalWeight - previousWeight + newWeight;
//    user.subYieldRewards = weightToReward(user.totalWeight, config.yieldRewardsPerWeight);
//
//    // update global variable
//    usersLockingWeight = usersLockingWeight - previousWeight + newWeight;
//
//    lfg.safeTransfer(_msgSender(), _amount);
//
//    // emit an event
//    emit Unstaked(_staker, _amount);
//  }

  /**
   * @dev Used internally, mostly by children implementations, see sync()
   *
   * @dev Updates smart contract state (`yieldRewardsPerWeight`, `lastYieldDistribution`),
   *      updates factory state via `updateTokenPerBlock`
   */
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
