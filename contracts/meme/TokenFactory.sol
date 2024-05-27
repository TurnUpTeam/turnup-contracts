// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Meme404} from "../meme/Meme404.sol";
import {MemeFT} from "./MemeFT.sol";

contract TokenFactory is Initializable {
  error Forbidden();
  error FactoryNotDeployed();

  address public memeFactory;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(address memeFactory_) public initializer {
    uint32 size;
    // solhint-disable-next-line no-inline-assembly
    assembly {
      size := extcodesize(memeFactory_)
    }
    if (size == 0) revert FactoryNotDeployed();
    memeFactory = memeFactory_;
  }

  function newMeme404(
    string calldata name,
    string calldata symbol,
    string calldata baseURI,
    uint256 baseUnit
  ) external returns (address) {
    if (msg.sender != memeFactory) revert Forbidden();
    Meme404 meme = new Meme404(name, symbol, baseURI, baseUnit, 0, msg.sender);
    meme.setFactory(msg.sender);
    return address(meme);
  }

  function newMemeFT(string calldata name, string calldata symbol) external returns (address) {
    if (msg.sender != memeFactory) revert Forbidden();
    MemeFT meme = new MemeFT(name, symbol);
    meme.setFactory(msg.sender);
    return address(meme);
  }
}