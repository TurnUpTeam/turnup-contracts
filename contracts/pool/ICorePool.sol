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

  event Synchronized(uint256 yieldRewardsPerWeight, uint256 lastYieldDistribution);
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

  struct RewardsConfig {
    uint256 tokensPerBlock;
    uint256 blocksPerUpdate;
    uint256 initBlock;
    uint256 endBlock;
    uint256 minLockTime;
    uint256 totalReserved;
    uint256 distributedRewards;
    uint256 totalYieldRewards;
    uint256 yieldRewardsPerWeight;
    uint256 decayFactor;
    uint256 lastRatioUpdate;
    uint256 usersLockingWeight;
    uint256 lastYieldDistribution;
  }

  function stakeAfterMint(address _staker, uint256 _amount, uint64 _lockUntil) external;

  function getConfig() external view returns (RewardsConfig memory);

}
