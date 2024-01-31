// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Author : Francesco Sullo < francesco@superpower.io>
// (c) Superpower Labs Inc.

import {AddressUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import {SafeMathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import {PFPAsset} from "./PFPAsset.sol";
import {LFGToken} from "../token/LFGToken.sol";

//import {console} from "hardhat/console.sol";

contract PFPFactory is OwnableUpgradeable, ReentrancyGuardUpgradeable, IERC721Receiver {
  using AddressUpgradeable for address;
  using SafeMathUpgradeable for uint256;
  using SafeERC20Upgradeable for LFGToken;

  event CollectionChange(address collection, uint256 initialPrice, bool native);
  event Bid(address collection, uint256 tokenId, uint256 price, uint256 bidAt, address bidder);

  error UnableToTransferFunds();
  error ZeroAddress();
  error InsufficientFunds();
  error AuctionIsOver();
  error AuctionIsNotOver();
  error NotTheWinner();
  error CollectionNotListed();
  error AssetNotFound();

  LFGToken internal _lfg;

  struct Collection {
    uint256 initialPrice;
    bool native;
  }

  struct Item {
    uint256 price;
    uint32 bidAt;
    address bidder;
  }

  mapping(address => Collection) internal _collections;
  mapping(address => mapping(uint256 => Item)) internal _items;

  function initialize(address lfg_) public initializer {
    __Ownable_init();
    _lfg = LFGToken(lfg_);
  }

  function initialPrice(address collection_) public view returns (uint256) {
    return _collections[collection_].initialPrice;
  }

  function isNative(address collection_) public view returns (bool) {
    return _collections[collection_].native;
  }

  function item(address collection_, uint256 tokenId_) public view returns (Item memory) {
    return _items[collection_][tokenId_];
  }

  function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
    return this.onERC721Received.selector;
  }

  // setting the price, in LFG and MATIC, for a collection adds the collection to the managed collections
  function setCollection(address collection_, uint256 initialPrice_, bool native_) external virtual onlyOwner {
    _collections[collection_] = Collection(initialPrice_, native_);
    emit CollectionChange(collection_, initialPrice_, native_);
  }

  function getCollection(address collection_) public view virtual returns (Collection memory) {
    return _collections[collection_];
  }

  function getPrice(address collection_, uint256 tokenId_) external view virtual returns (uint256) {
    uint256 price = _items[collection_][tokenId_].price + _items[collection_][tokenId_].price / 10;
    if (price == 0) {
      price = _collections[collection_].initialPrice;
    }
    return price;
  }

  function bid(address collection_, uint256 tokenId) external payable nonReentrant {
    Collection memory collection = _collections[collection_];
    if (collection.initialPrice == 0) revert CollectionNotListed();
    Item memory _item = _items[collection_][tokenId];
    if (PFPAsset(collection_).ownerOf(tokenId) != address(this)) {
      // the factory must own the asset
      revert AssetNotFound();
    }
    uint256 newPrice = collection.initialPrice;
    uint256 fee;
    if (_item.price > 0) {
      if (uint256(_item.bidAt) + 1 hours < block.timestamp) revert AuctionIsOver();
      newPrice = _item.price + _item.price / 10;
      fee = (newPrice * 5) / 110;
    }
    _items[collection_][tokenId] = Item(newPrice, uint32(block.timestamp), _msgSender());
    emit Bid(collection_, tokenId, newPrice, block.timestamp, _msgSender());
    if (collection.native) {
      if (msg.value < newPrice) revert InsufficientFunds();
      if (msg.value > newPrice) {
        // The user may send more than the current price to be sure that
        // the transaction will not fail if the price has increased in the meantime.
        // If there is a surplus we send it back to the user:
        (bool success, ) = _msgSender().call{value: msg.value - newPrice}("");
        if (!success) revert UnableToTransferFunds();
        // ^ In this case we reverts to try to anticipate further issues later
      }
      if (newPrice != collection.initialPrice) {
        // Not the first bid.
        (bool success, ) = _item.bidder.call{value: newPrice - fee}("");
        if (!success) {
          // ^ We ignore failures. If not, a bidder can use a smart contract to make a bid without
          // implementing a receive function. That would cause the call to fail, making impossible
          // for any other to make a bid over the asset
        }
      }
    } else {
      // If the user approves more than strictly required, they can be able to make a
      // successful bid even if the price has increased in the meantime.
      LFGToken(_lfg).safeTransferFrom(_msgSender(), address(this), newPrice);
      if (newPrice != collection.initialPrice) {
        // Not the first bid.
        LFGToken(_lfg).transfer(_item.bidder, newPrice - fee);
        // ^ We use transfer to ignore the failure for the same reasons as above
      }
    }
  }

  function claim(address collection_, uint256 tokenId_) external nonReentrant {
    Item memory _item = _items[collection_][tokenId_];
    if (uint256(_item.bidAt) + 1 hours > block.timestamp) revert AuctionIsNotOver();
    if (_item.bidder != _msgSender()) revert NotTheWinner();
    PFPAsset(collection_).safeTransferFrom(address(this), _item.bidder, tokenId_);
  }

  function withdrawProceeds(address beneficiary, bool native, uint256 amount) external virtual onlyOwner nonReentrant {
    if (beneficiary == address(0)) revert ZeroAddress();
    if (native) {
      if (amount == 0) {
        amount = address(this).balance;
      }
      if (amount > address(this).balance) revert InsufficientFunds();
      (bool success, ) = beneficiary.call{value: amount}("");
      if (!success) revert UnableToTransferFunds();
    } else {
      uint256 balance = LFGToken(_lfg).balanceOf(address(this));
      if (amount == 0) {
        amount = balance;
      }
      if (amount > balance) revert InsufficientFunds();
      LFGToken(_lfg).safeTransfer(beneficiary, amount);
    }
  }
}
