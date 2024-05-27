// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {DN404Mirror} from "dn404/src/DN404Mirror.sol"; 
import {IERC7631Mirror} from "./IERC7631Mirror.sol";

contract Meme404Mirror is DN404Mirror {
  constructor(address deployer) DN404Mirror(deployer) {}

  function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
    return interfaceId == type(IERC7631Mirror).interfaceId || super.supportsInterface(interfaceId);
  }
}