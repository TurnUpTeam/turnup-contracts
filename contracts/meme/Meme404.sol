// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {DN404} from "dn404/src/DN404.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {LibString} from "solady/src/utils/LibString.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";
import {Meme404Mirror} from "./Meme404Mirror.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract Meme404 is DN404, Ownable, Initializable {
  error InvalidBaseUnit();
  error NotAuthorized();
  error ZeroAddress();

  event TokenURIUpdated(string uri);

  string private _name;
  string private _symbol;
  string private _baseURI;
  uint256 private _baseUnit;

  address public factory;

  modifier onlyFactory() {
    if (factory == address(0) || factory != msg.sender) revert NotAuthorized();
    _;
  }

  function initialize(
    string memory name_,
    string memory symbol_,
    string memory baseURI_,
    uint256 baseUnit_,
    uint96 initialTokenSupply,
    address initialSupplyOwner,
    address mirrorImplementation
  ) public initializer {
    if (baseUnit_ < 1e18) revert InvalidBaseUnit();

    _name = name_;
    _symbol = symbol_;
    _baseURI = baseURI_;
    _baseUnit = baseUnit_;

    _initializeOwner(msg.sender);

    Meme404Mirror memeMirrorProxy = new Meme404Mirror(mirrorImplementation);
    Meme404Mirror memeMirror = Meme404Mirror(payable(address(memeMirrorProxy)));
    memeMirror.initialize(address(this));

    address mirror = address(memeMirror);
    _initializeDN404(initialTokenSupply, initialSupplyOwner, mirror);
  }

  function setFactory(address factory_) external onlyOwner {
    if (factory_ == address(0)) revert ZeroAddress();
    factory = factory_;
  }

  // Amount of token balance that is equal to one NFT
  function _unit() internal view virtual override returns (uint256) {
    return _baseUnit;
  }

  function name() public view virtual override returns (string memory) {
    return _name;
  }

  function symbol() public view virtual override returns (string memory) {
    return _symbol;
  }

  function _tokenURI(uint256 tokenId) internal view virtual override returns (string memory) {
    string memory uri;
    if (bytes(_baseURI).length != 0) {
      uri = string(abi.encodePacked(_baseURI, LibString.toString(tokenId)));
    }
    return uri;
  }

  function mint(address to, uint256 amount) public onlyFactory {
    _mint(to, amount);
  }

  function burn(uint256 amount) external {
    _burn(msg.sender, amount);
  }

  function setBaseURI(string calldata baseURI_) public onlyFactory {
    _baseURI = baseURI_;
  }

  function withdraw(address beneficiary) public onlyFactory {
    SafeTransferLib.safeTransferAllETH(beneficiary);
  }
}
