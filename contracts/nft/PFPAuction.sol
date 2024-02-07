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

contract PFPAuction is OwnableUpgradeable, ReentrancyGuardUpgradeable, IERC721Receiver {
  using AddressUpgradeable for address;
  using SafeMathUpgradeable for uint256;
  using SafeERC20Upgradeable for LFGToken;

  event ItemForAuction(
    address tokenAddress,
    uint256 tokenId,
    uint256 initialPrice,
    bool native,
    uint256 startTime,
    uint256 endTime
  );
  event Bid(address tokenAddress, uint256 tokenId, uint256 price, uint256 bidAt, address bidder);

  error UnableToTransferFunds();
  error ZeroAddress();
  error InsufficientFunds();
  error AuctionIsOver();
  error AuctionIsNotOver();
  error NotTheWinner();
  error CollectionNotListed();
  error AssetNotFound();
  error AuctionIsActive();
  error InvalidInput();

  struct Item {
    uint256 price;
    uint256 startTime;
    uint256 endTime;
    uint256 bidAt;
    address bidder;
    bool native;
  }

  LFGToken internal _lfg;
  mapping(address => mapping(uint256 => Item)) internal _items;
  uint256 public nativeFees;
  uint256 public lfgFees;

  function initialize(address lfg_) public initializer {
    __Ownable_init();
    _lfg = LFGToken(lfg_);
  }

  function getItem(address tokenAddress, uint256 tokenId) external view returns (Item memory) {
    return _items[tokenAddress][tokenId];
  }

  function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
    return this.onERC721Received.selector;
  }

  function setItemForAuction(
    address tokenAddress,
    uint256 tokenId,
    uint256 initialPrice,
    bool native,
    uint256 startTime,
    uint256 endTime
  ) public virtual onlyOwner {
    if (PFPAsset(tokenAddress).ownerOf(tokenId) != address(this)) {
      // the auction must own the asset
      revert AssetNotFound();
    }
    if (_items[tokenAddress][tokenId].bidder != address(0)) {
      // the asset has already received at least a bid
      revert AuctionIsActive();
    }
    _items[tokenAddress][tokenId] = Item({
      price: initialPrice,
      native: native,
      startTime: startTime,
      endTime: endTime,
      bidAt: 0,
      bidder: address(0)
    });
    emit ItemForAuction(tokenAddress, tokenId, initialPrice, native, startTime, endTime);
  }

  function setItemsForAuction(
    address[] calldata tokenAddresses,
    uint256[] calldata tokenIds,
    uint256[] calldata initialPrices,
    bool[] calldata natives,
    uint256[] calldata startTimes,
    uint256[] calldata endTimes
  ) external virtual onlyOwner {
    if (
      tokenAddresses.length != tokenIds.length ||
      tokenAddresses.length != initialPrices.length ||
      tokenAddresses.length != natives.length ||
      tokenAddresses.length != startTimes.length ||
      tokenAddresses.length != endTimes.length
    ) {
      revert InvalidInput();
    }
    for (uint256 i = 0; i < tokenAddresses.length; i++) {
      setItemForAuction(tokenAddresses[i], tokenIds[i], initialPrices[i], natives[i], startTimes[i], endTimes[i]);
    }
  }

  function getNextPrice(address tokenAddress, uint256 tokenId) public view virtual returns (uint256) {
    uint256 price = _items[tokenAddress][tokenId].price;
    if (_items[tokenAddress][tokenId].bidder != address(0)) {
      price += price / 10;
    }
    return price;
  }

  function auctionEndTime(address tokenAddress, uint256 tokenId) public view virtual returns (uint256) {
    Item storage item = _items[tokenAddress][tokenId];
    uint256 endTime = item.endTime;
    if (item.bidAt > 0 && (item.bidAt > endTime || endTime - item.bidAt < 1 hours)) {
      endTime = item.bidAt + 1 hours;
    }
    return endTime;
  }

  function isAuctionOver(address tokenAddress, uint256 tokenId) public view virtual returns (bool) {
    return block.timestamp > auctionEndTime(tokenAddress, tokenId);
  }

  function bid(address tokenAddress, uint256 tokenId) external payable nonReentrant {
    Item storage _item = _items[tokenAddress][tokenId];
    if (PFPAsset(tokenAddress).ownerOf(tokenId) != address(this)) {
      // the auction must own the asset
      revert AssetNotFound();
    }
    if (isAuctionOver(tokenAddress, tokenId)) revert AuctionIsOver();
    uint256 price = getNextPrice(tokenAddress, tokenId);
    address previousBidder = _item.bidder;
    uint256 fee = previousBidder == address(0) ? 0 : (price * 5) / 110;
    _item.price = price;
    _item.bidAt = block.timestamp;
    _item.bidder = _msgSender();
    if (_item.native) {
      nativeFees += fee;
    } else {
      lfgFees += fee;
    }
    emit Bid(tokenAddress, tokenId, price, block.timestamp, _msgSender());
    if (_item.native) {
      if (msg.value < price) revert InsufficientFunds();
      if (msg.value > price) {
        // The user may send more than the current price to be sure that
        // the transaction will not fail if the price has increased in the meantime.
        // If there is a surplus we send it back to the user:
        (bool success, ) = _msgSender().call{value: msg.value - price}("");
        if (!success) revert UnableToTransferFunds();
        // ^ In this case we reverts to try to anticipate further issues later
      }
      if (previousBidder != address(0)) {
        // Not the first bid.
        (bool success, ) = previousBidder.call{value: price - fee}("");
        if (!success) {
          // ^ We ignore failures. If not, a bidder can use a smart contract to make a bid without
          // implementing a receive function. That would cause the call to fail, making impossible
          // for any other to make a bid over the asset
        }
      }
    } else {
      // If the user approves more than strictly required, they can be able to make a
      // successful bid even if the price has increased in the meantime.
      LFGToken(_lfg).safeTransferFrom(_msgSender(), address(this), price);
      if (previousBidder != address(0)) {
        // Not the first bid.
        LFGToken(_lfg).transfer(previousBidder, price - fee);
        // ^ We use transfer to ignore the failure for the same reasons as above
      }
    }
  }

  function claim(address tokenAddress, uint256 tokenId) external nonReentrant {
    Item memory _item = _items[tokenAddress][tokenId];
    if (!isAuctionOver(tokenAddress, tokenId)) revert AuctionIsNotOver();
    if (_item.bidder != _msgSender()) revert NotTheWinner();
    PFPAsset(tokenAddress).safeTransferFrom(address(this), _item.bidder, tokenId);
  }

  function withdrawProceeds(address beneficiary, bool native, uint256 amount) external virtual onlyOwner nonReentrant {
    if (beneficiary == address(0)) revert ZeroAddress();
    if (native) {
      if (amount == 0) {
        amount = nativeFees;
      }
      if (amount > address(this).balance) revert InsufficientFunds();
      nativeFees -= amount;
      (bool success, ) = beneficiary.call{value: amount}("");
      if (!success) revert UnableToTransferFunds();
    } else {
      uint256 balance = LFGToken(_lfg).balanceOf(address(this));
      if (amount == 0) {
        amount = lfgFees;
      }
      if (amount > balance) revert InsufficientFunds();
      lfgFees -= amount;
      LFGToken(_lfg).safeTransfer(beneficiary, amount);
    }
  }

  function burnLfgProceeds(uint256 amount) external virtual onlyOwner nonReentrant {
    uint256 balance = LFGToken(_lfg).balanceOf(address(this));
    if (amount == 0) {
      amount = lfgFees;
    }
    if (amount > balance) revert InsufficientFunds();
    lfgFees -= amount;
    LFGToken(_lfg).burn(amount);
  }
}
