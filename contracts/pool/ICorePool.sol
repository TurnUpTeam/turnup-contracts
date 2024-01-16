// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

interface ICorePool {
  /**
   * @dev Fired in _stake() and stake()
   *
   * @param _from token holder address, the tokens will be returned to that address
   * @param amount amount of tokens staked
   */
  event Staked(address indexed _from, uint256 amount);

  /**
   * @dev Fired in _updateStakeLock() and updateStakeLock()
   *
   * @param staker an address which updated the stake lock
   * @param depositId updated deposit ID
   * @param lockedFrom deposit locked from value
   * @param lockedUntil updated deposit locked until value
   */
  event StakeLockUpdated(address staker, uint256 depositId, uint64 lockedFrom, uint64 lockedUntil);

  /**
   * @dev Fired in _unstake() and unstake()
   *
   * @param _to an address which received the unstaked tokens, usually token holder
   * @param amount amount of tokens unstaked
   */
  event Unstaked(address indexed _to, uint256 amount);

  /**
   * @dev Fired in _sync(), sync() and dependent functions (stake, unstake, etc.)
   *
   * @param yieldRewardsPerWeight updated yield rewards per weight value
   * @param lastYieldDistribution usually, current block number
   */
  event Synchronized(uint256 yieldRewardsPerWeight, uint64 lastYieldDistribution);

  /**
   * @dev Fired in _processRewards(), processRewards() and dependent functions (stake, unstake, etc.)
   *
   * @param _to an address which claimed the yield reward
   * @param amount amount of yield paid
   */
  event YieldClaimed(address indexed _to, uint256 amount);

  /**
   * @dev Fired in setWeight()
   *
   * @param _fromVal old pool weight value
   * @param _toVal new pool weight value
   */
  event PoolWeightUpdated(uint32 _fromVal, uint32 _toVal);

  /**
   * @dev Fired in changePoolWeight()
   *
   * @param weight new pool weight
   */
  event WeightUpdated(uint32 weight);

  /**
   * @dev Fired in updateSYNPerBlock()
   *
   * @param newTokenPerBlock new TOKEN/block value
   */
  event TokenRatioUpdated(uint256 newTokenPerBlock);

  /**
   * @dev Deposit is a key data structure used in staking,
   *      it represents a unit of stake with its amount, weight and term (time interval)
   */
  struct Deposit {
    // @dev token amount staked
    uint256 tokenAmount;
    // @dev stake weight
    uint256 weight;
    // @dev locking period - from
    uint64 lockedFrom;
    // @dev locking period - until
    uint64 lockedUntil;
  }

  /// @dev Data structure representing token holder using a pool
  struct User {
    // @dev Total staked amount
    uint256 tokenAmount;
    // @dev Total weight
    uint256 totalWeight;
    // @dev Auxiliary variable for yield calculation
    uint256 subYieldRewards;
    // @dev Auxiliary variable for vault rewards calculation
    uint256 subVaultRewards;
    // @dev An array of holder's deposits
    Deposit[] deposits;
  }

  function pendingYieldRewards(address _staker) external view returns (uint256);

  function balanceOf(address _user) external view returns (uint256);

  function getDeposit(address _user, uint256 _depositId) external view returns (Deposit memory);

  function getDepositsLength(address _user) external view returns (uint256);

  function blockNumber() external view returns (uint256);

  function now256() external view returns (uint256);

  function stake(uint256 _amount, uint64 _lockUntil) external;

  function unstake(uint256 _depositId, uint256 _amount) external;

  function updateStakeLock(uint256 depositId, uint64 lockedUntil) external;

  function sync() external;

  function processRewards() external;

  function getStakeWeight(uint256 lockedTime, uint256 addedAmount) external pure returns (uint256);

  function weightToReward(uint256 _weight, uint256 rewardPerWeight) external returns (uint256);

  function rewardToWeight(uint256 reward, uint256 rewardPerWeight) external returns (uint256);

  function shouldUpdateRatio() external view returns (bool);

  function updateLFGPerBlock() external;

  function overrideLFGPerBlock(uint192 _tokenPerBlock) external;

  function overrideBlocksPerUpdate(uint32 _blocksPerUpdate) external;

  function overrideEndblock(uint32 _endBlock) external;

  function overrideDecayFactor(uint32 _decayFactor) external;

  function setMinLockTime(uint256 _minLockTime) external;
}
