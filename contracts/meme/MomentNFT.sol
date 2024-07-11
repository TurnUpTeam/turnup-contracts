// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721Burnable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC4906} from "../utils/IERC4906.sol";
import {MomentFactory} from "./MomentFactory.sol";

contract MomentNFT is IERC4906, Ownable, ERC721Burnable
{ 
  error InvalidTokenId(); 
  error NotAuthorized();
  error ZeroAddress();

  event TokenURIUpdated(string uri); 

  string private baseURI;  
  uint256 public lastTokenId;
  uint256 public clubId;
  
  address public factory;

  modifier onlyFactory() {
    if (factory == address(0) || factory != msg.sender) revert NotAuthorized();
    _;
  }

  constructor(
    uint256 clubId_, 
    string memory name_, 
    string memory symbol_, 
    string memory baseURI_
    ) ERC721(name_, symbol_) {
    baseURI = baseURI_;
    clubId = clubId_;
  }
 
  function setFactory(address factory_) external onlyOwner {
    if (factory_ == address(0)) revert ZeroAddress();
    factory = factory_;
  }
 
  function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
    return interfaceId == type(IERC4906).interfaceId || super.supportsInterface(interfaceId);
  }
  
  function setBaseURI(string calldata baseURI_) public onlyFactory {
    baseURI = baseURI_;
  }

  function _baseURI() internal view virtual override returns (string memory) {
    return baseURI;
  }
  
  function updateBaseURI(string calldata uri) external virtual onlyFactory {
    baseURI = uri;
    if (lastTokenId > 0) {
      emit BatchMetadataUpdate(1, lastTokenId);
    }
    emit TokenURIUpdated(uri);
  }

  function contractURI() public view returns (string memory) {
    return string(abi.encodePacked(baseURI, "info"));
  }

  function preMint(address recipient) external onlyFactory returns (uint256) {
    uint256 tokenId = ++lastTokenId;
    _safeMint(recipient, tokenId);
    return tokenId;
  }

  function _afterTokenTransfer(address from, address to, uint256 firstTokenId, uint256 /*batchSize*/) internal virtual override {
    MomentFactory(factory).onNFTTransfer(clubId, from, to, firstTokenId);
  }
}
