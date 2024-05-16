// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {DN404Mirror} from "dn404/src/DN404Mirror.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract Meme404Mirror is DN404Mirror, Initializable {
  error AlreadyInitialized();

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(address deployer) DN404Mirror(deployer) {
    _disableInitializers();
  }

  function initialize(address deployer) public initializer {
    DN404NFTStorage storage $ = _getDN404NFTStorage();
    $.deployer = deployer;
  }
}
