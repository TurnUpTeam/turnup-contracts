// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {KeysPoolMock} from "./KeysPoolMock.sol";

contract LFGTokenMock is ERC20, Ownable {
  KeysPoolMock public keysPool;

  constructor() ERC20("LFG Token", "LFG") {}

  function setPool(address pool) public {
    keysPool = KeysPoolMock(pool);
  }

  function mint(address to, uint256 amount) public {
    _mint(to, amount);
  }
}
