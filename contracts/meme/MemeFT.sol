// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MemeFT is ERC20, Ownable {
  
  error ZeroAddress();
  error NotAuthorized();
  
  address public factory;

  modifier onlyFactory() {
    if (factory == address(0) || factory != msg.sender) revert NotAuthorized();
    _;
  }

  constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {
  }

  function mint(address to, uint256 amount) public onlyFactory {
    _mint(to, amount);
  }
 
 
  function setFactory(address factory_) external onlyOwner {
    if (factory_ == address(0)) revert ZeroAddress();
    factory = factory_;
  }
}
