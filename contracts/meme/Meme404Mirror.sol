// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {DN404Mirror} from "dn404/src/DN404Mirror.sol"; 

interface IERC7631Mirror {
  function baseERC20() external view returns (address);
}

contract Meme404Mirror is DN404Mirror {
  constructor(address deployer) DN404Mirror(deployer) {}

  function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
    return interfaceId == type(IERC7631Mirror).interfaceId || super.supportsInterface(interfaceId);
  }
}