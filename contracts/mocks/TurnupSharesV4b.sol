// SPDX-License-Identifier: MIT

// for security it is better to lock the version
pragma solidity 0.8.19;

import {TurnupSharesV4} from "../TurnupSharesV4.sol";

contract TurnupSharesV4b is TurnupSharesV4 {
  function getVer() public pure virtual override returns (string memory) {
    return "v7.0.0";
  }
}
