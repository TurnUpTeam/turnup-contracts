// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Import SafeERC20
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import {LFGToken} from "../token/LFGToken.sol";

import {Rewards} from "./Rewards.sol";

//import {console} from "hardhat/console.sol";

/**
 * @title LFG Core Pool
 *        Original title: Illuvium Core Pool
 *
 * @author Pedro Bergamini, reviewed by Basil Gorin
 * Adapted for TurnUP by the TurnUP Team
 */

contract CorePool is Rewards {
  using SafeERC20Upgradeable for LFGToken;

  /// @dev Token holder storage, maps token holder address to their data record
  mapping(address => User) public users;

  /**
   * @dev When we know beforehand that staking is done for a year, and fraction of the year locked is one,
   *      we use simplified calculation and use the following constant instead previos one
   */
  // solhint-disable-next-line
  //  uint256 internal _yearStakeWeightMultiplier;

  LFGToken public lfg;

  address public factory;

  error PoolTokenAddressNotSet();
  error TokenBlockNotSet();
  error BlocksPerUpdateNotSet();
  error InvalidEndBlock();
  error PoolWeightNotSet();
  error NotAuthorized();
  error TooEarlyToUnstake();

  function initialize(
    address _lfg,
    uint256 _initBlock,
    uint256 _minLockTime,
    uint256 _totalReserved,
    address _factory
  ) public initializer {
    __Ownable_init();
    __Pausable_init();
    __Rewards_init(_initBlock, _minLockTime, _totalReserved);
    if (_lfg == address(0)) revert PoolTokenAddressNotSet();
    lfg = LFGToken(_lfg);
    factory = _factory;
  }

  /**
   * @notice Calculates current yield rewards value available for address specified
   *
   * @param _staker an address to calculate yield rewards value for
   * @return calculated yield reward value for the given address
   */
  function pendingYieldRewards(address _staker) external view returns (uint256) {
    // `newYieldRewardsPerWeight` will store stored or recalculated value for `yieldRewardsPerWeight`
    uint256 newYieldRewardsPerWeight;

    // if smart contract state was not updated recently, `yieldRewardsPerWeight` value
    // is outdated and we need to recalculate it in order to calculate pending rewards correctly
    if (blockNumber() > _config.lastYieldDistribution && _config.usersLockingWeight != 0) {
      uint256 multiplier = blockNumber() > _config.endBlock
        ? _config.endBlock - _config.lastYieldDistribution
        : blockNumber() - _config.lastYieldDistribution;
      uint256 rewards = multiplier * _config.tokensPerBlock;

      // recalculated value for `yieldRewardsPerWeight`
      newYieldRewardsPerWeight = rewardToWeight(rewards, _config.usersLockingWeight) + _config.yieldRewardsPerWeight;
    } else {
      // if smart contract state is up to date, we don't recalculate
      newYieldRewardsPerWeight = _config.yieldRewardsPerWeight;
    }

    // based on the rewards per weight value, calculate pending rewards;
    User storage user = users[_staker];
    uint256 pending = weightToReward(user.totalWeight, newYieldRewardsPerWeight) - user.subYieldRewards;
    return pending;
  }

  /**
   * @notice Returns total staked token balance for the given address
   *
   * @param _user an address to query balance for
   * @return total staked token balance
   */
  function balanceOf(address _user) external view returns (uint256) {
    // read specified user token amount and return
    return users[_user].tokenAmount;
  }

  /**
   * @notice Returns information on the given deposit for the given address
   *
   * @dev See getDepositsLength
   *
   * @param _user an address to query deposit for
   * @param _depositId zero-indexed deposit ID for the address specified
   * @return deposit info as Deposit structure
   */
  function getDeposit(address _user, uint256 _depositId) external view returns (Deposit memory) {
    // read deposit at specified index and return
    return users[_user].deposits[_depositId];
  }

  /**
   * @notice Returns number of deposits for the given address. Allows iteration over deposits.
   *
   * @dev See getDeposit
   *
   * @param _user an address to query deposit length for
   * @return number of deposits for the given address
   */
  function getDepositsLength(address _user) external view returns (uint256) {
    // read deposits array length and return
    return users[_user].deposits.length;
  }

  /**
   * @notice Stakes specified amount of tokens for the specified amount of time,
   *      and pays pending yield rewards if any
   *
   * @dev Requires amount to stake to be greater than zero
   *
   * @param _amount amount of tokens to stake
   * @param _lockUntil stake period as unix timestamp; zero means no locking
   */
  function stake(uint256 _amount, uint64 _lockUntil) external whenNotPaused {
    // delegate call to an internal function
    _stake(_msgSender(), _amount, _lockUntil, _msgSender());
  }

  /**
   * @notice Unstakes specified amount of tokens, and pays pending yield rewards if any
   *
   * @dev Requires amount to unstake to be greater than zero
   *
   * @param _depositId deposit ID to unstake from, zero-indexed
   * @param _amount amount of tokens to unstake
   */
  function unstake(uint256 _depositId, uint256 _amount) external whenNotPaused {
    // delegate call to an internal function
    _unstake(_msgSender(), _depositId, _amount);
  }

  /**
   * @notice Extends locking period for a given deposit
   *
   * @dev Requires new lockedUntil value to be:
   *      higher than the current one, and
   *      in the future, but
   *      no more than 1 year in the future
   *
   * @param depositId updated deposit ID
   * @param lockedUntil updated deposit locked until value
   */
  function updateStakeLock(uint256 depositId, uint64 lockedUntil) external whenNotPaused {
    // delegate call to an internal function
    _updateStakeLock(_msgSender(), depositId, lockedUntil);
  }

  /**
   * @notice Service function to synchronize pool state with current time
   *
   * @dev Can be executed by anyone at any time, but has an effect only when
   *      at least one block passes between synchronizations
   * @dev Executed internally when staking, unstaking, processing rewards in order
   *      for calculations to be correct and to reflect state progress of the contract
   * @dev When timing conditions are not met (executed too frequently, or after factory
   *      end block), function doesn't throw and exits silently
   */
  function sync() external whenNotPaused {
    // delegate call to an internal function
    _sync();
  }

  /**
   * @notice Service function to calculate and pay pending yield rewards to the sender
   *
   * @dev Can be executed by anyone at any time, but has an effect only when
   *      executed by deposit holder and when at least one block passes from the
   *      previous reward processing
   * @dev Executed internally when staking and unstaking, executes sync() under the hood
   *      before making further calculations and payouts
   * @dev When timing conditions are not met (executed too frequently, or after factory
   *      end block), function doesn't throw and exits silently
   *
   */
  function processRewards() external whenNotPaused {
    // delegate call to an internal function
    _processRewards(_msgSender(), true);
  }

  error InvalidMinLockTime();

  //  function setMinLockTime(uint256 _minLockTime_) public whenNotPaused onlyOwner {
  //    if (_minLockTime_ > 364 days) revert InvalidMinLockTime();
  //    config.minLockTime = _minLockTime_;
  //  }

  error ZeroAmount();
  error InvalidLockInternal();

  /**
   * @notice Stakes specified amount of tokens for the specified amount of time,
   *      and pays pending yield rewards if any
   *
   * @dev Requires amount to stake to be greater than zero
   *
   * @param _amount amount of tokens to stake
   * @param _lockUntil stake period as unix timestamp; zero means no locking
   */
  function stakeAfterMint(address _staker, uint256 _amount, uint64 _lockUntil) external override whenNotPaused {
    if (_msgSender() != factory) revert NotAuthorized();
    // delegate call to an internal function
    _stake(_staker, _amount, _lockUntil, factory);
  }

  /**
   * @dev Used internally, mostly by children implementations, see stake()
   *
   * @param _staker an address which stakes tokens and which will receive them back
   * @param _amount amount of tokens to stake
   * @param _lockUntil stake period as unix timestamp; zero means no locking
   */
  function _stake(address _staker, uint256 _amount, uint64 _lockUntil, address lfgSender) internal virtual {
    // validate the inputs
    if (_amount == 0) revert ZeroAmount();

    // we need to the limit of max locking time to limit the yield bonus
    if (_lockUntil < now256() + _config.minLockTime || _lockUntil - now256() > 365 days) revert InvalidLockInternal();
    // update smart contract state
    _sync();

    // get a link to user data struct, we will write to it later
    User storage user = users[_staker];
    // process current pending rewards if any
    if (user.tokenAmount > 0) {
      _processRewards(_staker, false);
    }

    // in most of the cases added amount `addedAmount` is simply `_amount`
    // however for deflationary tokens this can be different
    // read the current balance
    uint256 previousBalance = lfg.balanceOf(address(this));
    // transfer `_amount`; note: some tokens may get burnt here
    // the lfgSender can be the user or the factory
    lfg.safeTransferFrom(lfgSender, address(this), _amount);
    // read new balance, usually this is just the difference `previousBalance - _amount`
    uint256 newBalance = lfg.balanceOf(address(this));
    // calculate real amount taking into account deflation
    uint256 addedAmount = newBalance - previousBalance;

    uint64 lockFrom = _lockUntil > 0 ? uint64(now256()) : 0;
    uint64 lockUntil = _lockUntil;

    // stake weight formula rewards for locking
    uint256 stakeWeight = getStakeWeight(lockUntil - lockFrom, addedAmount);

    // makes sure stakeWeight is valid
    assert(stakeWeight > 0);

    // create and save the deposit (append it to deposits array)
    Deposit memory deposit = Deposit({
      tokenAmount: addedAmount,
      weight: stakeWeight,
      lockedFrom: lockFrom,
      lockedUntil: lockUntil
    });
    // deposit ID is an index of the deposit in `deposits` array
    user.deposits.push(deposit);

    // update user record
    user.tokenAmount += addedAmount;
    user.totalWeight += stakeWeight;
    user.subYieldRewards = weightToReward(user.totalWeight, _config.yieldRewardsPerWeight);

    // update global variable
    _config.usersLockingWeight += stakeWeight;

    // emit an event
    emit Staked(_staker, _amount, lockFrom, lockUntil);
  }

  error AmountExceedsStake();

  function _unstake(address _staker, uint256 _depositId, uint256 _amount) internal virtual {
    // verify an amount is set
    if (_amount == 0) revert ZeroAmount();

    // get a link to user data struct, we will write to it later
    User storage user = users[_staker];
    // get a link to the corresponding deposit, we may write to it later
    Deposit storage stakeDeposit = user.deposits[_depositId];
    // deposit structure may get deleted, so we save isYield flag to be able to use it

    if (stakeDeposit.lockedUntil > now256()) revert TooEarlyToUnstake();

    // verify available balance
    // if staker address ot deposit doesn't exist this check will fail as well
    if (stakeDeposit.tokenAmount < _amount) revert AmountExceedsStake();

    // update smart contract state
    _sync();
    // and process current pending rewards if any
    _processRewards(_staker, false);

    // recalculate deposit weight
    uint256 previousWeight = stakeDeposit.weight;
    uint256 newWeight = (((stakeDeposit.lockedUntil - stakeDeposit.lockedFrom) * _weightMultiplier) /
      365 days +
      _weightMultiplier) * (stakeDeposit.tokenAmount - _amount);

    // update the deposit, or delete it if its depleted
    if (stakeDeposit.tokenAmount - _amount == 0) {
      delete user.deposits[_depositId];
    } else {
      stakeDeposit.tokenAmount -= _amount;
      stakeDeposit.weight = newWeight;
    }

    // update user record
    user.tokenAmount -= _amount;
    user.totalWeight = user.totalWeight - previousWeight + newWeight;
    user.subYieldRewards = weightToReward(user.totalWeight, _config.yieldRewardsPerWeight);

    // update global variable
    _config.usersLockingWeight = _config.usersLockingWeight - previousWeight + newWeight;

    lfg.safeTransfer(_msgSender(), _amount);

    // emit an event
    emit Unstaked(_staker, _amount);
  }

  /**
   * @dev Used internally, mostly by children implementations, see processRewards()
   *
   * @param _staker an address which receives the reward (which has staked some tokens earlier)
   * @return pendingYield the rewards calculated and optionally re-staked
   */
  function _processRewards(address _staker, bool withUpdate) internal virtual returns (uint256 pendingYield) {
    if (withUpdate) {
      _sync();
    }
    User storage user = users[_staker];
    // calculate pending yield rewards, this value will be returned
    pendingYield = _pendingYieldRewards(user.totalWeight);

    // if pending yield is zero - just return silently
    if (pendingYield == 0) return 0;

    // get link to a user data structure, we will write into it later

    lfg.transfer(_staker, pendingYield);
    if (withUpdate) {
      user.subYieldRewards = weightToReward(user.totalWeight, _config.yieldRewardsPerWeight);
    }
    // emit an event
    emit YieldClaimed(_staker, pendingYield);
  }

  error LockShouldBeInTheFuture();
  error InvalidNewLock();
  error MaxLockPeriodIs365Days();

  /**
   * @dev See updateStakeLock()
   *
   * @param _staker an address to update stake lock
   * @param _depositId updated deposit ID
   * @param _lockedUntil updated deposit locked until value
   */
  function _updateStakeLock(address _staker, uint256 _depositId, uint64 _lockedUntil) internal virtual {
    // synchronizes pool state
    _sync();
    // validate the input time
    if (_lockedUntil <= now256()) revert LockShouldBeInTheFuture();
    // get a link to user data struct, we will write to it later
    User storage user = users[_staker];
    if (user.tokenAmount > 0) {
      _processRewards(_staker, false);
    }
    // get a link to the corresponding deposit, we may write to it later
    Deposit storage stakeDeposit = user.deposits[_depositId];

    // validate the input against deposit structure
    if (_lockedUntil <= stakeDeposit.lockedUntil) revert InvalidNewLock();

    // verify locked from and locked until values
    if (stakeDeposit.lockedFrom == 0) {
      if (_lockedUntil - now256() > 365 days) revert MaxLockPeriodIs365Days();
      stakeDeposit.lockedFrom = uint64(now256());
    } else {
      if (_lockedUntil - stakeDeposit.lockedFrom > 365 days) revert MaxLockPeriodIs365Days();
    }

    // update locked until value, calculate new weight
    stakeDeposit.lockedUntil = _lockedUntil;
    uint256 newWeight = (((stakeDeposit.lockedUntil - stakeDeposit.lockedFrom) * _weightMultiplier) /
      365 days +
      _weightMultiplier) * stakeDeposit.tokenAmount;

    // save previous weight
    uint256 previousWeight = stakeDeposit.weight;
    // update weight
    stakeDeposit.weight = newWeight;

    // update user total weight, sub yield rewards and global locking weight
    user.totalWeight = user.totalWeight - previousWeight + newWeight;
    user.subYieldRewards = weightToReward(user.totalWeight, _config.yieldRewardsPerWeight);
    _config.usersLockingWeight = _config.usersLockingWeight - previousWeight + newWeight;

    // emit an event
    emit StakeLockUpdated(_staker, _depositId, stakeDeposit.lockedFrom, _lockedUntil);
  }

  uint256[50] private __gap;
}
