// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {MemeFT} from "../meme/MemeFT.sol"; 
import {MomentNFT} from "../meme/MomentNFT.sol"; 

contract MomentToken is Initializable {
  error Forbidden();
  error FactoryNotDeployed();

  address public factory;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(address Factory_) public initializer {
    uint32 size;
    // solhint-disable-next-line no-inline-assembly
    assembly {
      size := extcodesize(Factory_)
    }
    if (size == 0) revert FactoryNotDeployed();
    factory = Factory_;
  }

  function newMomentFT(string calldata name, string calldata symbol) external returns (address) {
    if (msg.sender != factory) revert Forbidden();
    MemeFT meme = new MemeFT(name, symbol);
    meme.setFactory(msg.sender);
    return address(meme);
  }

  function newMomentNFT(uint256 clubId, string calldata name, string calldata symbol, string calldata baseURI) external returns (address) {
    if (msg.sender != factory) revert Forbidden();
    MomentNFT nft = new MomentNFT(clubId, name, symbol, baseURI);
    nft.setFactory(msg.sender);
    return address(nft);
  }
}