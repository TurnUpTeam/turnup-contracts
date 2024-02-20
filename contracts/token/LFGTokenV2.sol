// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {DN404} from "dn404/src/DN404.sol";
import {DN404Mirror} from "dn404/src/DN404Mirror.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {LibString} from "solady/src/utils/LibString.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";

contract LFGTokenV2 is DN404, Ownable {
  error NotAuthorized();
  error NoZeroAddress();
  error SupplyOverflow();
  error AlreadySet();

  struct LFGStorage {
    address factory;
    uint96 maxSupply;
  }

  string private _name;
  string private _symbol;
  string private _baseURI;

  address public factory;

  modifier onlyFactory() {
    if (factory == address(0) || factory != msg.sender) revert NotAuthorized();
    _;
  }

  constructor(string memory name_, string memory symbol_, uint96 initialTokenSupply, address initialSupplyOwner) {
    _initializeOwner(msg.sender);

    _name = name_;
    _symbol = symbol_;

    address mirror = address(new DN404Mirror(msg.sender));
    _initializeDN404(initialTokenSupply, initialSupplyOwner, mirror);
  }

  function setFactory(address _factory) external onlyOwner {
    if (_factory == address(0)) revert NoZeroAddress();
    if (factory != address(0)) revert AlreadySet();
    factory = _factory;
  }

  function _unit() internal view virtual override returns (uint256) {
    // since LFG total supply is 4B, we may associate it to a 10,000 NFT supply
    return 40000 * 1e18;
  }

  function name() public view override returns (string memory) {
    return _name;
  }

  function symbol() public view override returns (string memory) {
    return _symbol;
  }

  function tokenURI(uint256 tokenId) public view override returns (string memory) {
    string memory uri;
    if (bytes(_baseURI).length != 0) {
      uri = string(abi.encodePacked(_baseURI, LibString.toString(tokenId)));
    }
    return uri;
  }

  function mint(address to, uint256 amount) public onlyFactory {
    _mint(to, amount);
  }

  function burn(address account, uint256 amount) external onlyFactory {
    _burn(account, amount);
  }

  function setBaseURI(string calldata baseURI_) public onlyOwner {
    _baseURI = baseURI_;
  }

  function withdraw() public onlyOwner {
    SafeTransferLib.safeTransferAllETH(msg.sender);
  }
}
