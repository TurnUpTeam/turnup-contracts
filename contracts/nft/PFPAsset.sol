// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Author: Francesco Sullo <francesco@superpower.io>
// (c) Superpower Labs Inc.

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC721BurnableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ERC721LockableUpgradeable} from "@ndujalabs/erc721lockable/ERC721LockableUpgradeable.sol";
import {ValidatableUpgradeable} from "../utils/ValidatableUpgradeable.sol";
import {IERC4906} from "../utils/IERC4906.sol";

contract PFPAsset is
  IERC4906,
  OwnableUpgradeable,
  ERC721LockableUpgradeable,
  ERC721BurnableUpgradeable,
  ValidatableUpgradeable
{
  event TokenURIFrozen();
  event TokenURIUpdated(string uri);
  error FrozenTokenURI();
  error InvalidTokenId();
  error InvalidMaxSupply();

  string private _baseTokenURI;
  bool private _baseTokenURIFrozen;
  uint256 public maxSupply;
  uint256 public lastTokenId;

  address public factory;

  // solhint-disable-next-line
  function __PFPAsset_init(
    string memory name_,
    string memory symbol_,
    string memory tokenUri,
    bool defaultLocked_
  ) public onlyInitializing {
    __Ownable_init();
    __ERC721Lockable_init(name_, symbol_, defaultLocked_);
    __Validatable_init();
    _baseTokenURI = tokenUri;
  }

  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 tokenId,
    uint256 batchSize
  ) internal override(ERC721LockableUpgradeable, ERC721Upgradeable) {
    super._beforeTokenTransfer(from, to, tokenId, batchSize);
  }

  function supportsInterface(
    bytes4 interfaceId
  ) public view virtual override(ERC721LockableUpgradeable, ERC721Upgradeable) returns (bool) {
    return interfaceId == type(IERC4906).interfaceId || super.supportsInterface(interfaceId);
  }

  function setFactory(address _factory) external onlyOwner {
    factory = _factory;
  }

  // solhint-disable-next-line no-empty-blocks
  function _canSetDefaultLocked() internal view override onlyOwner {}

  function _baseURI() internal view virtual override returns (string memory) {
    return _baseTokenURI;
  }

  function setMaxSupply(uint256 _maxSupply) external onlyOwner {
    if (_maxSupply == 0) {
      // Freeze the supply at the current distributed supply
      maxSupply = totalSupply();
    } else if (_maxSupply > totalSupply()) {
      // It also allows to increase the maxSupply, if needed
      maxSupply = _maxSupply;
    } else revert InvalidMaxSupply();
  }

  function updateTokenURI(string memory uri) external virtual onlyOwner {
    if (_baseTokenURIFrozen) {
      revert FrozenTokenURI();
    }
    _baseTokenURI = uri;
    if (maxSupply > 0) {
      // this assumes that the tokenId starts from 0
      // Override it, if not
      emit BatchMetadataUpdate(0, maxSupply - 1);
    }
    emit TokenURIUpdated(uri);
  }

  function freezeTokenURI() external onlyOwner {
    _baseTokenURIFrozen = true;
    emit TokenURIFrozen();
  }

  function contractURI() public view returns (string memory) {
    return string(abi.encodePacked(_baseTokenURI, "info"));
  }

  // the owner must distribute the auctionable tokens to the factory to allow the factory to operate
  function preMint(address recipient, uint256 amount) external onlyOwner {
    uint256 tokenId = lastTokenId;
    for (uint256 i = 0; i < amount; i++) {
      _safeMint(recipient, ++tokenId);
      if (maxSupply > 0 && tokenId > maxSupply) revert InvalidTokenId();
    }
    lastTokenId = tokenId;
  }

  uint256[50] private __gap;
}
