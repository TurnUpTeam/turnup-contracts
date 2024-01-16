// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// @author Francesco Sullo <francesco@sullo.co>

interface IERC20Lockable {
  /**
   * @dev Emitted when tokenId is locked
   */
  event Lock(address indexed account, uint256 indexed amount, address indexed _locker, uint256 lockedUntil);

  /**
   * @dev Emitted when tokenId is unlocked
   */
  event Unlock(address indexed account, uint256 indexed amount, address indexed _locker);

  /**
   * @dev Lock the amount if msg.sender is owner or approved
   *   The locker MUST be owner of approved to lock the amount.
   *   If the locker has already locked some amount, the lockedUntil MUST be 0 and the amount added to the locked amount,
   *   without changing the existing lockedUntil. If, when adding to an existing lock the lockedUntil is not zero, it MUST revert.
   *
   *   To avoid forever locks, the contract should set a maximum lockedUntil, and the function MUST revert if the lockedUntil
   *   is greater than the maximum lockedUntil.
   */
  function lock(address locker, uint256 amount, uint256 lockedUntil) external;

  /**
   * @dev Unlocks the amount before the expiration. msg.sender MUST be a locker
   *   It MUST revert if the unlocking amount is not locked by the msg.sender.
   */
  function unlock(address account, uint256 amount, uint256 lockedUntil) external;

  /**
   * @dev Moves `amount` tokens from the caller's account to `to` and locks the amount
   *
   * Returns a boolean value indicating whether the operation succeeded.
   *
   * Emits a {Transfer} event.
   */
  function transferAndLock(address to, uint256 amount, uint256 lockedUntil) external;

  /**
   * @dev Moves `amount` tokens from `from` to `to` using the
   * allowance mechanism. `amount` is then deducted from the caller's
   * allowance. It also locks the amount.
   *
   * Returns a boolean value indicating whether the operation succeeded.
   *
   * Emits a {Transfer} event.
   */
  function transferFromAndLock(address from, address to, uint256 amount, uint256 lockedUntil) external;

  /**
   * @dev Unlocks `amount` and moves it from the caller's account to `to`
   *   msg.sender MUST be a locker.
   */
  function unlockAndTransfer(address to, uint256 amount, uint256 tokenUntil) external;

  /**
   * @dev It also unlocks `amount` and moves it from `from` to `to` using the
   * allowance mechanism. `amount` is then deducted from the caller's
   * allowance.
   *
   *   msg.sender MUST be a locker.
   *
   * Returns a boolean value indicating whether the operation succeeded.
   *
   * Emits a {Transfer} event.
   */
  function unlockAndTransferFrom(address from, address to, uint256 amount, uint256 tokenUntil) external;

  /**
   * @dev Returns the balance of account locked by locker, if any, and when it unlocks
   */
  function availableBalanceOf(address account) external view returns (uint256);
}
