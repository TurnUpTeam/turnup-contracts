// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC1967Upgrade} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Upgrade.sol";
import {Proxy} from "@openzeppelin/contracts/proxy/Proxy.sol";

error InvalidImplementation();

contract Meme404Proxy is Proxy, ERC1967Upgrade {
  address immutable DEFAULT_IMPL;

  constructor(address _defaultImplementation) {
    if (_defaultImplementation == address(0)) revert InvalidImplementation();
    DEFAULT_IMPL = _defaultImplementation;
  }

  function _implementation() internal view virtual override returns (address) {
    address implementation = ERC1967Upgrade._getImplementation();

    if (implementation == address(0)) return DEFAULT_IMPL;

    return implementation;
  }

  function _beforeFallback() internal virtual override {
    super._beforeFallback();
    if (msg.data.length == 0) {
      if (ERC1967Upgrade._getImplementation() == address(0)) {
        ERC1967Upgrade._upgradeTo(DEFAULT_IMPL);
        _delegate(DEFAULT_IMPL);
      }
    }
  }
}
