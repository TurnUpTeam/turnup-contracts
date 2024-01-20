// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20BurnableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {ERC20Lockable} from "../erc20Lockable/ERC20Lockable.sol";

contract LFGToken is ERC20Lockable, OwnableUpgradeable, ERC20BurnableUpgradeable {
  error NotAuthorized();
  error InvalidInitialSupply();
  error InvalidAmountReservedToPool();
  error NoZeroAddress();
  error OverReservedAmount();

  address public factory;
  uint256 public maxSupply;
  uint256 public amountReservedToGame;

  uint256 public amountReservedToPool;
  address public pool;
  uint256 public amountMintedByPool;

  uint256 public amountReservedToSharesPool;
  address public sharesPool;
  uint256 public amountMintedBySharesPool;

  modifier onlyFactory() {
    if (factory == address(0) || factory != _msgSender()) revert NotAuthorized();
    _;
  }

  modifier onlyPool() {
    if (pool == address(0) || pool != _msgSender()) revert NotAuthorized();
    _;
  }

  modifier onlySharesPool() {
    if (sharesPool == address(0) || sharesPool != _msgSender()) revert NotAuthorized();
    _;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(
    address tokenHolder,
    uint256 maxSupply_,
    uint256 initialSupply,
    uint256 amountReservedToPool_,
    uint256 amountReservedToSharesPool_,
    uint256 maxLockTime_
  ) public initializer {
    __ERC20Lockable_init("TurnUp $LFG", "LFG", maxLockTime_);
    __ERC20Burnable_init();
    __Ownable_init();
    maxSupply = maxSupply_;
    amountReservedToPool = amountReservedToPool_;
    amountReservedToSharesPool = amountReservedToSharesPool_;
    amountReservedToGame = maxSupply_ - (initialSupply + amountReservedToPool_ + amountReservedToSharesPool_);
    _mint(tokenHolder, initialSupply);
  }

  function expandMaxSupply(uint256 amount) external onlyFactory {
    maxSupply = maxSupply + amount;
  }

  function countLocksOf(address account) public view returns (uint256) {
    return _lockers[account].length;
  }

  function locksOf(address account) public view returns (LockedAmount[] memory) {
    return _locks[factory][account];
  }

  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 amount
  ) internal virtual override(ERC20Lockable, ERC20Upgradeable) {
    super._beforeTokenTransfer(from, to, amount);
  }

  function setFactory(address _factory) external onlyOwner {
    if (_factory == address(0)) revert NoZeroAddress();
    factory = _factory;
  }

  function setPool(address pool_) external onlyOwner {
    if (pool_ == address(0)) revert NoZeroAddress();
    pool = pool_;
  }

  function setSharesPool(address sharesPool_) external onlyOwner {
    if (sharesPool_ == address(0)) revert NoZeroAddress();
    sharesPool = sharesPool_;
  }

  function mint(address to, uint256 amount) external onlyFactory {
    _mint(to, amount);
  }

  function revertMint(address account, uint256 amount, uint256 lockedUntil) external onlyFactory {
    (bool found, uint256 i) = _lockIndex(account, _msgSender(), lockedUntil);
    if (!found || _locks[_msgSender()][account][i].lockedUntil < block.timestamp) revert LockNotFound();
    else _unlock(account, amount, i);
    _burn(account, amount);
  }

  function burnTo(address account, uint256 amount) external onlyFactory {
    _burn(account, amount);
  }

  function mintAndLock(address to, uint256 amount, uint256 lockedUntil) external onlyFactory {
    _mint(to, amount);
    if (lockedUntil != 0) {
      _lock(to, amount, factory, lockedUntil);
    }
  }

  function mintFromPool(address to, uint256 amount) external onlyPool {
    _mint(to, amount);
    amountMintedByPool += amount;
    if (amountMintedByPool > amountReservedToPool) revert OverReservedAmount();
  }

  function mintFromSharesPool(address to, uint256 amount) external onlySharesPool {
    _mint(to, amount);
    amountMintedBySharesPool += amount;
    if (amountMintedBySharesPool > amountReservedToSharesPool) revert OverReservedAmount();
  }
}
