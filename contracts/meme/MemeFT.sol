// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract MemeFT is Initializable, ERC20Upgradeable, ERC20PermitUpgradeable, OwnableUpgradeable {
  error ZeroAddress();
  error NotAuthorized();

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(string memory name_, string memory symbol_, address initialOwner_) public initializer {
    __ERC20_init(name_, symbol_);
    __ERC20Permit_init(name_);
    _transferOwnership(initialOwner_);
  }

  function mint(address to, uint256 amount) public onlyOwner {
    _mint(to, amount);
  } 
}
