// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20BurnableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract LFGToken is OwnableUpgradeable, ERC20Upgradeable, ERC20BurnableUpgradeable {
  error NotAuthorized();
  error InvalidInitialSupply();
  error InvalidAmountReservedToPool();
  error NoZeroAddress();
  error OverReservedAmount();
  error AlreadySet();

  address public factory;
  uint256 public maxSupply;
  uint256 public amountReservedToFactory;

  uint256 public amountReservedToPool;
  address public pool;
  uint256 public amountMintedByPool;

  uint256 public amountReservedToSharesPool;
  address public sharesPool;
  uint256 public amountMintedBySharesPool;

  uint256 public amountMintedByFactory;

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
    uint256 amountReservedToSharesPool_
  ) public initializer {
    __ERC20_init("TurnUp $LFG", "LFG");
    __ERC20Burnable_init();
    __Ownable_init();
    maxSupply = maxSupply_;
    amountReservedToPool = amountReservedToPool_;
    amountReservedToSharesPool = amountReservedToSharesPool_;
    amountReservedToFactory = maxSupply_ - (initialSupply + amountReservedToPool_ + amountReservedToSharesPool_);
    _mint(tokenHolder, initialSupply);
    // it mints the tokens to itself to distribute them later to the pools
    _mint(address(this), maxSupply - initialSupply);
  }

  function expandMaxSupply(uint256 amount) external onlyFactory {
    maxSupply = maxSupply + amount;
  }

  function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override {
    super._beforeTokenTransfer(from, to, amount);
  }

  function setFactory(address _factory) external onlyOwner {
    if (_factory == address(0)) revert NoZeroAddress();
    if (factory != address(0)) revert AlreadySet();
    factory = _factory;
    _transfer(address(this), factory, amountReservedToFactory);
  }

  function setPool(address pool_) external onlyOwner {
    if (pool_ == address(0)) revert NoZeroAddress();
    if (pool != address(0)) revert AlreadySet();
    pool = pool_;
    _transfer(address(this), pool, amountReservedToPool);
  }

  function setSharesPool(address sharesPool_) external onlyOwner {
    if (sharesPool_ == address(0)) revert NoZeroAddress();
    if (sharesPool != address(0)) revert AlreadySet();
    sharesPool = sharesPool_;
    _transfer(address(this), sharesPool, amountReservedToSharesPool);
  }

  function burnFromFactory(address account, uint256 amount) external onlyFactory {
    _burn(account, amount);
    // We reduce it making it deflationary.
    // Will revert if trying to burn more than the reserved amount
    amountReservedToFactory -= amount;
  }

  function name() public view virtual override returns (string memory) {
    return "LFG";
  }
}
