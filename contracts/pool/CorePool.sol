// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Import Ownable2Step from OpenZeppelin
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

// Import SafeERC20
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import {LFGToken} from "../token/LFGToken.sol";

import {ICorePool} from "./ICorePool.sol";

//import { console} from "hardhat/console.sol";

contract CorePool is ICorePool, Ownable2StepUpgradeable {
  using SafeERC20Upgradeable for LFGToken;

  uint256 private _minLockTime;

  /// @dev Token holder storage, maps token holder address to their data record
  mapping(address => User) public users;

  /// @dev Used to calculate yield rewards
  /// @dev This value is different from "reward per token" used in locked pool
  /// @dev Note: stakes are different in duration and "weight" reflects that
  uint256 public yieldRewardsPerWeight;

  /// @dev Used to calculate yield rewards, keeps track of the tokens weight locked in staking
  uint256 public usersLockingWeight;

  uint256 public totalYieldReward;

  /**
   * @dev Stake weight is proportional to deposit amount and time locked, precisely
   *      "deposit amount wei multiplied by (fraction of the year locked plus one)"
   * @dev To avoid significant precision loss due to multiplication by "fraction of the year" [0, 1],
   *      weight is stored multiplied by 1e6 constant, as an integer
   * @dev Corner case 1: if time locked is zero, weight is deposit amount multiplied by 1e6
   * @dev Corner case 2: if time locked is one year, fraction of the year locked is one, and
   *      weight is a deposit amount multiplied by 2 * 1e6
   */
  // solhint-disable-next-line
  uint256 internal constant WEIGHT_MULTIPLIER = 1e6;

  /**
   * @dev When we know beforehand that staking is done for a year, and fraction of the year locked is one,
   *      we use simplified calculation and use the following constant instead previos one
   */
  // solhint-disable-next-line
  uint256 internal constant YEAR_STAKE_WEIGHT_MULTIPLIER = 2 * WEIGHT_MULTIPLIER;

  /**
   * @dev Rewards per weight are stored multiplied by 1e20, as integers.
   */
  // solhint-disable-next-line
  uint256 internal constant REWARD_PER_WEIGHT_MULTIPLIER = 1e20;

  LFGToken public lfg;

  struct Config {
    /**
     * @dev TOKEN/block determines yield farming reward base
     *      used by the yield pools controlled by the factory
     */
    uint192 tokenPerBlock;
    /// @dev CorePool.sol weight, 100 for TOKEN pool or 900 for TOKEN/ETH
    uint32 weight;
    /// @dev Block number of the last yield distribution event
    uint64 lastYieldDistribution;
    /**
     * @dev The yield is distributed proportionally to pool weights;
     *      total weight is here to help in determining the proportion
     */
    uint32 totalWeight;
    /**
     * @dev TOKEN/block decreases by 3% every blocks/update (set to 91252 blocks during deployment);
     */
    uint32 blocksPerUpdate;
    /**
     * @dev End block is the last block when TOKEN/block can be decreased;
     *      it is implied that yield farming stops after that block
     */
    uint32 endBlock;
    uint32 decayFactor;
    /**
     * @dev Each time the TOKEN/block ratio gets updated, the block number
     *      when the operation has occurred gets recorded into `lastRatioUpdate`
     * @dev This block number is then used to check if blocks/update `blocksPerUpdate`
     *      has passed when decreasing yield reward by 3%
     */
    uint32 lastRatioUpdate;
  }

  Config public config;

  address public factory;

  error PoolTokenAddressNotSet();
  error TokenBlockNotSet();
  error BlocksPerUpdateNotSet();
  error InitBlockNotSet();
  error InvalidEndBlock();
  error PoolWeightNotSet();
  error NotAuthorized();

  function initialize(
    address _lfg,
    uint192 _tokenPerBlock,
    uint32 _blocksPerUpdate,
    uint32 _initBlock,
    uint32 _endBlock,
    uint32 _weight,
    uint256 _minLockTime_,
    address _factory
  ) public initializer {
    __Ownable_init();
    if (_lfg == address(0)) revert PoolTokenAddressNotSet();
    lfg = LFGToken(_lfg);

    if (_tokenPerBlock == 0) revert TokenBlockNotSet();
    if (_blocksPerUpdate == 0) revert BlocksPerUpdateNotSet();
    if (_initBlock == 0) revert InitBlockNotSet();
    if (_endBlock <= _initBlock) revert InvalidEndBlock();
    if (_weight == 0) revert PoolWeightNotSet();
    // save the inputs into internal state variables

    overrideLFGPerBlock(_tokenPerBlock);
    overrideBlocksPerUpdate(_blocksPerUpdate);
    config.lastRatioUpdate = _initBlock;
    config.endBlock = _endBlock;

    config.weight = _weight;
    config.totalWeight = _weight;
    config.lastYieldDistribution = _initBlock;

    setMinLockTime(_minLockTime_);
    config.decayFactor = 97;
    factory = _factory;
  }

  function minLockTime() external view override returns (uint256) {
    return _minLockTime;
  }

  /**
   * @notice Calculates current yield rewards value available for address specified
   *
   * @param _staker an address to calculate yield rewards value for
   * @return calculated yield reward value for the given address
   */
  function pendingYieldRewards(address _staker) external view override returns (uint256) {
    // `newYieldRewardsPerWeight` will store stored or recalculated value for `yieldRewardsPerWeight`
    uint256 newYieldRewardsPerWeight;

    // if smart contract state was not updated recently, `yieldRewardsPerWeight` value
    // is outdated and we need to recalculate it in order to calculate pending rewards correctly
    if (blockNumber() > config.lastYieldDistribution && usersLockingWeight != 0) {
      uint256 multiplier = blockNumber() > config.endBlock
        ? config.endBlock - config.lastYieldDistribution
        : blockNumber() - config.lastYieldDistribution;
      uint256 rewards = (multiplier * config.weight * config.tokenPerBlock) / config.totalWeight;

      // recalculated value for `yieldRewardsPerWeight`
      newYieldRewardsPerWeight = rewardToWeight(rewards, usersLockingWeight) + yieldRewardsPerWeight;
    } else {
      // if smart contract state is up to date, we don't recalculate
      newYieldRewardsPerWeight = yieldRewardsPerWeight;
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
  function balanceOf(address _user) external view override returns (uint256) {
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
  function getDeposit(address _user, uint256 _depositId) external view override returns (Deposit memory) {
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
  function getDepositsLength(address _user) external view override returns (uint256) {
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
  function stake(uint256 _amount, uint64 _lockUntil) external override {
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
  function unstake(uint256 _depositId, uint256 _amount) external override {
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
  function updateStakeLock(uint256 depositId, uint64 lockedUntil) external override {
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
  function sync() external override {
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
  function processRewards() external override {
    // delegate call to an internal function
    _processRewards(_msgSender());
  }

  /**
   * @dev Executed by the factory to modify pool weight; the factory is expected
   *      to keep track of the total pools weight when updating
   *
   * @dev Set weight to zero to disable the pool
   *
   * @param _weight new weight to set for the pool
   */
  function _setWeight(uint32 _weight) internal {
    // emit an event logging old and new weight values
    emit PoolWeightUpdated(config.weight, _weight);

    // set the new weight value
    config.weight = _weight;
  }

  /**
   * @dev Similar to public pendingYieldRewards, but performs calculations based on
   *      current smart contract state only, not taking into account any additional
   *      time/blocks which might have passed
   *
   * @param _staker an address to calculate yield rewards value for
   * @return pending calculated yield reward value for the given address
   */
  function _pendingYieldRewards(address _staker) internal view returns (uint256 pending) {
    // read user data structure into memory
    User storage user = users[_staker];

    // and perform the calculation using the values read
    return weightToReward(user.totalWeight, yieldRewardsPerWeight) - user.subYieldRewards;
  }

  error InvalidMinLockTime();

  function setMinLockTime(uint256 _minLockTime_) public override onlyOwner {
    if (_minLockTime_ > 364 days) revert InvalidMinLockTime();
    _minLockTime = _minLockTime_;
  }

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
  function stakeAfterMint(address _staker, uint256 _amount, uint64 _lockUntil) external override {
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
    if (_lockUntil < now256() + _minLockTime || _lockUntil - now256() > 365 days) revert InvalidLockInternal();
    // update smart contract state
    _sync();

    // get a link to user data struct, we will write to it later
    User storage user = users[_staker];
    // process current pending rewards if any
    if (user.tokenAmount > 0) {
      _processRewards(_staker);
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

    // set the `lockFrom` and `lockUntil` taking into account that
    // zero value for `_lockUntil` means "no locking" and leads to zero values
    // for both `lockFrom` and `lockUntil`
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
    user.subYieldRewards = weightToReward(user.totalWeight, yieldRewardsPerWeight);

    // update global variable
    usersLockingWeight += stakeWeight;

    // emit an event
    emit Staked(_staker, _amount);
  }

  function getStakeWeight(uint256 lockedTime, uint256 addedAmount) public pure override returns (uint256) {
    return ((lockedTime * WEIGHT_MULTIPLIER) / 365 days + WEIGHT_MULTIPLIER) * addedAmount;
  }

  /**
   * @dev Converts stake weight (not to be mixed with the pool weight) to
   *      TOKEN reward value, applying the 10^12 division on weight
   *
   * @param _weight stake weight
   * @param rewardPerWeight TOKEN reward per weight
   * @return reward value normalized to 10^12
   */
  function weightToReward(uint256 _weight, uint256 rewardPerWeight) public pure override returns (uint256) {
    // apply the formula and return
    return (_weight * rewardPerWeight) / REWARD_PER_WEIGHT_MULTIPLIER;
  }

  /**
   * @dev Converts reward TOKEN value to stake weight (not to be mixed with the pool weight),
   *      applying the 10^12 multiplication on the reward
   *      - OR -
   * @dev Converts reward TOKEN value to reward/weight if stake weight is supplied as second
   *      function parameter instead of reward/weight
   *
   * @param reward yield reward
   * @param rewardPerWeight reward/weight (or stake weight)
   * @return stake weight (or reward/weight)
   */
  function rewardToWeight(uint256 reward, uint256 rewardPerWeight) public pure override returns (uint256) {
    // apply the reverse formula and return
    return (reward * REWARD_PER_WEIGHT_MULTIPLIER) / rewardPerWeight;
  }

  /**
   * @dev Testing time-dependent functionality is difficult and the best way of
   *      doing it is to override block number in helper test smart contracts
   *
   * @return `block.number` in mainnet, custom values in testnets (if overridden)
   */
  function blockNumber() public view virtual override returns (uint256) {
    // return current block number
    return block.number;
  }

  /**
   * @dev Testing time-dependent functionality is difficult and the best way of
   *      doing it is to override time in helper test smart contracts
   *
   * @return `block.timestamp` in mainnet, custom values in testnets (if overridden)
   */
  function now256() public view virtual override returns (uint256) {
    // return current block timestamp
    return block.timestamp;
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

    // verify available balance
    // if staker address ot deposit doesn't exist this check will fail as well
    if (stakeDeposit.tokenAmount < _amount) revert AmountExceedsStake();

    // update smart contract state
    _sync();
    // and process current pending rewards if any
    _processRewards(_staker);

    // recalculate deposit weight
    uint256 previousWeight = stakeDeposit.weight;
    uint256 newWeight = (((stakeDeposit.lockedUntil - stakeDeposit.lockedFrom) * WEIGHT_MULTIPLIER) /
      365 days +
      WEIGHT_MULTIPLIER) * (stakeDeposit.tokenAmount - _amount);

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
    user.subYieldRewards = weightToReward(user.totalWeight, yieldRewardsPerWeight);

    // update global variable
    usersLockingWeight = usersLockingWeight - previousWeight + newWeight;

    lfg.safeTransfer(_msgSender(), _amount);

    // emit an event
    emit Unstaked(_staker, _amount);
  }

  /**
   * @dev Used internally, mostly by children implementations, see sync()
   *
   * @dev Updates smart contract state (`yieldRewardsPerWeight`, `lastYieldDistribution`),
   *      updates factory state via `updateLFGPerBlock`
   */
  function _sync() internal virtual {
    // update TOKEN per block value in factory if required
    if (shouldUpdateRatio()) {
      updateLFGPerBlock();
    }
    // check bound conditions and if these are not met -
    // exit silently, without emitting an event
    if (config.lastYieldDistribution >= config.endBlock) {
      return;
    }
    if (blockNumber() <= config.lastYieldDistribution) {
      return;
    }
    // if locking weight is zero - update only `lastYieldDistribution` and exit
    if (usersLockingWeight == 0) {
      config.lastYieldDistribution = uint64(blockNumber());
      return;
    }
    // to calculate the reward we need to know how many blocks passed, and reward per block
    uint256 currentBlock = blockNumber() > config.endBlock ? config.endBlock : blockNumber();
    uint256 blocksPassed = currentBlock - config.lastYieldDistribution;

    // calculate the reward
    uint256 rewards = (blocksPassed * config.tokenPerBlock * config.weight) / config.totalWeight;

    totalYieldReward += rewards;

    // update rewards per weight and `lastYieldDistribution`
    yieldRewardsPerWeight += rewardToWeight(rewards, usersLockingWeight);
    config.lastYieldDistribution = uint64(currentBlock);

    // emit an event
    emit Synchronized(yieldRewardsPerWeight, config.lastYieldDistribution);
  }

  function shouldUpdateRatio() public view override returns (bool) {
    // if yield farming period has ended
    if (blockNumber() > config.endBlock) {
      // TOKEN/block reward cannot be updated anymore
      return false;
    }

    // check if blocks/update (91252 blocks) have passed since last update
    return blockNumber() >= config.lastRatioUpdate + config.blocksPerUpdate;
  }

  error TooFrequent();

  function updateLFGPerBlock() public override {
    // checks if ratio can be updated i.e. if blocks/update (91252 blocks) have passed
    if (!shouldUpdateRatio()) revert TooFrequent();

    // decreases TOKEN/block reward by 3%
    config.tokenPerBlock = (config.tokenPerBlock * config.decayFactor) / 100;

    // set current block as the last ratio update block
    config.lastRatioUpdate = uint32(blockNumber());

    // emit an event
    emit TokenRatioUpdated(config.tokenPerBlock);
  }

  function overrideLFGPerBlock(uint192 _tokenPerBlock) public override onlyOwner {
    config.tokenPerBlock = _tokenPerBlock;
    // emit an event
    emit TokenRatioUpdated(config.tokenPerBlock);
  }

  function overrideBlocksPerUpdate(uint32 _blocksPerUpdate) public override onlyOwner {
    config.blocksPerUpdate = _blocksPerUpdate;
  }

  function overrideEndblock(uint32 _endBlock) public override onlyOwner {
    config.endBlock = _endBlock;
  }

  function overrideDecayFactor(uint32 _decayFactor) public override onlyOwner {
    config.decayFactor = _decayFactor;
  }

  /**
   * @dev Used internally, mostly by children implementations, see processRewards()
   *
   * @param _staker an address which receives the reward (which has staked some tokens earlier)
   * @return pendingYield the rewards calculated and optionally re-staked
   */
  function _processRewards(address _staker) internal virtual returns (uint256 pendingYield) {
    _sync();

    // calculate pending yield rewards, this value will be returned
    pendingYield = _pendingYieldRewards(_staker);

    // if pending yield is zero - just return silently
    if (pendingYield == 0) return 0;

    // get link to a user data structure, we will write into it later
    User storage user = users[_staker];

    lfg.transfer(_staker, pendingYield);

    user.subYieldRewards = weightToReward(user.totalWeight, yieldRewardsPerWeight);

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
      _processRewards(_staker);
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
    uint256 newWeight = (((stakeDeposit.lockedUntil - stakeDeposit.lockedFrom) * WEIGHT_MULTIPLIER) /
      365 days +
      WEIGHT_MULTIPLIER) * stakeDeposit.tokenAmount;

    // save previous weight
    uint256 previousWeight = stakeDeposit.weight;
    // update weight
    stakeDeposit.weight = newWeight;

    // update user total weight, sub yield rewards and global locking weight
    user.totalWeight = user.totalWeight - previousWeight + newWeight;
    user.subYieldRewards = weightToReward(user.totalWeight, yieldRewardsPerWeight);
    usersLockingWeight = usersLockingWeight - previousWeight + newWeight;

    // emit an event
    emit StakeLockUpdated(_staker, _depositId, stakeDeposit.lockedFrom, _lockedUntil);
  }

  uint256[50] private __gap;
}
