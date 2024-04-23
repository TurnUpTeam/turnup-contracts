// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC4906} from "@openzeppelin/contracts/interfaces/IERC4906.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Lockable} from "@ndujalabs/erc721lockable/ERC721Lockable.sol";
import {ERC721Burnable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";

contract MemeNft is IERC4906, ERC721Lockable, ERC721Burnable {
   
  error InvalidTokenId();
  error NotAuthorized();
  error IsBanTransfer();

  event TokenURIUpdated(string uri);

  string public baseTokenURI;
  uint256 public lastTokenId;
  address public factory;
  bool public isBanTransfer;

  modifier onlyFactory() {
    if (factory == address(0) || factory != _msgSender()) revert NotAuthorized();
    _;
  }

  constructor(
    string memory name_,
    string memory symbol_,
    string memory tokenURI_
  ) ERC721Lockable(name_, symbol_, false) {
    baseTokenURI = tokenURI_;
    isBanTransfer = true;
  }
 
  function setFactory(address factory_) external onlyOwner {
    factory = factory_;
  } 

  // solhint-disable-next-line no-empty-blocks
  function _canSetDefaultLocked() internal view override onlyOwner {}

  function _baseURI() internal view virtual override returns (string memory) {
    return baseTokenURI;
  }

  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 tokenId,
    uint256 batchSize
  ) internal override(ERC721Lockable, ERC721) {
    if (!isBanTransfer || from == address(0) || to == address(0)) { // must skip mint or burn
      super._beforeTokenTransfer(from, to, tokenId, batchSize);
    } else {
      revert IsBanTransfer();
    }
  }

  function setBanTransfer(bool isBan) external virtual onlyFactory {
    isBanTransfer = isBan;
  }

  function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721Lockable, ERC721, IERC165) returns (bool) {
    return interfaceId == type(IERC4906).interfaceId || super.supportsInterface(interfaceId);
  }
  
  function onMetaDataUpdate() public onlyFactory {
    if (lastTokenId > 0) {
      emit BatchMetadataUpdate(1, lastTokenId);
    }
  }

  function updateTokenURI(string memory uri) external virtual onlyFactory { 
    baseTokenURI = uri;
    onMetaDataUpdate(); 
    emit TokenURIUpdated(uri);
  }

  function contractURI() public view returns (string memory) {
    return string(abi.encodePacked(baseTokenURI, "info"));
  }

  function safeMint(address recipient, uint256 amount) external onlyFactory {
    uint256 tokenId = lastTokenId;
    for (uint256 i = 0; i < amount; i++) {
      _safeMint(recipient, ++tokenId); 
    }
    lastTokenId = tokenId;
  }

}