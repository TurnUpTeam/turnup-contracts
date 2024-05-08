// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {DN404Mirror} from "dn404/src/DN404Mirror.sol";

contract Meme404Mirror is DN404Mirror {
  error AlreadyInitialized();

  constructor(address deployer) DN404Mirror(deployer) {
    // the deployer of the implementation is ignored by the proxy
  }

  function init(address deployer) public {
    DN404NFTStorage storage $ = _getDN404NFTStorage();
    if ($.deployer != address(0)) {
      revert AlreadyInitialized();
    }
    $.deployer = deployer;
  }
}