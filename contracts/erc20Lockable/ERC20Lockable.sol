// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// @author Franncesco Sullo <francesco@sullo.co>

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {IERC20Lockable} from "./IERC20Lockable.sol";

//import {console} from "hardhat/console.sol";

contract ERC20Lockable is IERC20Lockable, Initializable, ERC20Upgradeable {
  error NotEnoughLockedAmount();
  error LockExpired();
  error LockNotFound();
  error TooManyLocks();
  error InsufficientAllowance();
  error LockTooLong();
  error MaxLockTimeCannotBeZero();

  struct LockedAmount {
    uint224 amount;
    uint32 lockedUntil;
  }

  struct Locker {
    address locker;
    uint32 locks;
  }

  mapping(address => mapping(address => LockedAmount[])) internal _locks;
  mapping(address => Locker[]) internal _lockers;
  uint256 public maxLockTime;

  function _beforeTokenTransfer(address from, address, uint256 amount) internal virtual override {
    if (from == address(0)) return;
    if (_lockers[_msgSender()].length == 0) return;
    if (amount > _availableBalanceOfWhileCleaning(from)) revert InsufficientAllowance();
  }

  // solhint-disable-next-line
  function __ERC20Lockable_init(string memory name, string memory symbol, uint256 maxLockTime_) public initializer {
    __ERC20_init(name, symbol);
    _setMaxLockTime(maxLockTime_);
  }

  function _setMaxLockTime(uint256 maxLockTime_) internal {
    if (maxLockTime_ == 0) revert MaxLockTimeCannotBeZero();
    maxLockTime = maxLockTime_;
  }

  function lock(address account, uint256 amount, uint256 lockedUntil) public override {
    if (lockedUntil > block.timestamp + maxLockTime) revert LockTooLong();
    _spendAllowance(account, _msgSender(), amount);
    _lock(account, amount, _msgSender(), lockedUntil);
  }

  function _lock(address account, uint256 amount, address locker, uint256 lockedUntil) internal {
    if (_locks[locker][account].length > 10) {
      // to avoid gas issues during loops
      revert TooManyLocks();
    }
    _locks[locker][account].push(LockedAmount(uint224(amount), uint32(lockedUntil)));
    emit Lock(account, amount, locker, lockedUntil);
    for (uint256 i = 0; i < _lockers[account].length; i++) {
      if (_lockers[account][i].locker == locker) {
        _lockers[account][i].locks++;
        return;
      }
    }
    _lockers[account].push(Locker(locker, 1));
  }

  function _lockIndex(address account, address locker, uint256 lockedUntil) internal view returns (bool, uint256) {
    for (uint256 i = 0; i < _locks[_msgSender()][account].length; i++) {
      if (_locks[locker][account][i].lockedUntil == lockedUntil) {
        return (true, i);
      }
    }
    return (false, 0);
  }

  function unlock(address account, uint256 amount, uint256 lockedUntil) public override {
    (bool found, uint256 i) = _lockIndex(account, _msgSender(), lockedUntil);
    if (!found) revert LockNotFound();
    if (_locks[_msgSender()][account][i].lockedUntil < block.timestamp) {
      _deleteLock(account, _msgSender(), i);
    } else {
      _unlock(account, amount, i);
    }
  }

  function _unlock(address account, uint256 amount, uint256 i) internal {
    if (_locks[_msgSender()][account][i].amount < amount) revert NotEnoughLockedAmount();
    if (_locks[_msgSender()][account][i].amount == amount) {
      _deleteLock(account, _msgSender(), i);
      emit Unlock(account, amount, _msgSender());
    } else {
      _locks[_msgSender()][account][i].amount -= uint224(amount);
      emit Unlock(account, amount, _msgSender());
    }
  }

  function _deleteLock(address account, address locker, uint256 i) internal {
    if (_locks[locker][account].length > 1) {
      _locks[locker][account][i] = _locks[locker][account][_locks[locker][account].length - 1];
      _locks[locker][account].pop();
    } else delete _locks[locker][account];
    _lockers[account][i] = _lockers[account][_lockers[account].length - 1];
    for (uint256 j = 0; j < _lockers[account].length; j++) {
      if (_lockers[account][j].locker == locker) {
        if (_lockers[account][j].locks > 1) _lockers[account][j].locks--;
        else {
          _lockers[account][j] = _lockers[account][_lockers[account].length - 1];
          _lockers[account].pop();
        }
        break;
      }
    }
  }

  function transferAndLock(address to, uint256 amount, uint256 lockedUntil) public override {
    transfer(to, amount);
    lock(to, amount, lockedUntil);
  }

  function transferFromAndLock(address from, address to, uint256 amount, uint256 lockedUntil) public override {
    transferFrom(from, to, amount);
    lock(to, amount, lockedUntil);
  }

  function unlockAndTransfer(address to, uint256 amount, uint256 tokenUntil) public override {
    unlock(_msgSender(), amount, tokenUntil);
    transfer(to, amount);
  }

  function unlockAndTransferFrom(address from, address to, uint256 amount, uint256 tokenUntil) public override {
    unlock(from, amount, tokenUntil);
    transferFrom(from, to, amount);
  }

  function availableBalanceOf(address account) public view override returns (uint256) {
    uint256 availableBalance = balanceOf(account);
    for (uint256 i = 0; i < _lockers[account].length; i++) {
      for (uint256 j = 0; j < _locks[_lockers[account][i].locker][account].length; j++) {
        if (_locks[_lockers[account][i].locker][account][j].lockedUntil > block.timestamp) {
          availableBalance -= _locks[_lockers[account][i].locker][account][j].amount;
        }
      }
    }
    return availableBalance;
  }

  // Called before a transfer.
  // Reduces the gas consumption if any lock is expired
  function _availableBalanceOfWhileCleaning(address account) internal returns (uint256) {
    uint256 availableBalance = balanceOf(account);
    // it can go out of gas if there are too many locks
    // That's why we have a limit of 10 locks per lockers
    // The number of lockers should be reasonable low or zero

    for (uint256 i = 0; i < _lockers[account].length; i++) {
      for (uint256 j = 0; j < _locks[_lockers[account][i].locker][account].length; j++) {
        if (_locks[_lockers[account][i].locker][account][j].lockedUntil > block.timestamp) {
          availableBalance -= _locks[_lockers[account][i].locker][account][j].amount;
        } else {
          _deleteLock(account, _msgSender(), i);
        }
      }
    }
    return availableBalance;
  }

  uint256[50] private __gap;
}
