// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {DN404} from "dn404/src/DN404.sol";

// only to calculate the size of DN404
contract DN404Mock is DN404 {
  function _tokenURI(uint256) internal view virtual override returns (string memory) {
    return "https://example.com";
  }

  function name() public view virtual override returns (string memory) {
    return "DN404";
  }

  function symbol() public view virtual override returns (string memory) {
    return "DN404";
  }
}