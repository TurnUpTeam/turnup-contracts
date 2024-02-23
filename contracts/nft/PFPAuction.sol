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
    uint256 endTime,
    uint256 deferredDuration
  );
  event Bid(
    address indexed tokenAddress,
    uint256 indexed tokenId,
    uint256 price,
    uint256 bidAt,
    address indexed bidder,
    uint256 newEndTime,
    uint256 previousPrice,
    address previousBidder,
    uint256 previousBidderRefund
  );
  event Claim(address indexed tokenAddress, uint256 indexed tokenId, address indexed winner, uint256 price);
  event BidFailed(address indexed tokenAddress, uint256 indexed tokenId, uint256 price, address indexed bidder);

  error UnableToTransferFunds();
  error ZeroAddress();
  error InsufficientFunds();
  error InsufficientFees();
  error AuctionIsOver();
  error AuctionIsNotOver();
  error NotTheWinner();
  error CollectionNotListed();
  error AssetNotFound();
  error AuctionIsActive();
  error InvalidInput();
  error ItemPriceTypeNotIdentical();
  error CannotBatchBidSameItemTwice();
  error AuctionNotStarted();

  // Optimized to reduce storage consumption
  struct Item {
    // 1st word
    uint96 price;
    address bidder;
    // 2nd word
    uint32 startTime;
    uint32 endTime;
    uint32 deferredDuration;
    uint32 bidAt;
    bool native;
  }

  LFGToken internal _lfg;
  mapping(address => mapping(uint256 => Item)) internal _items;
  uint256 public nativeFees;
  uint256 public lfgFees;

  // used to avoid double bidding during batch bidding
  mapping(address => mapping(uint256 => bool)) private _checked;

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
    // This is encoded using bitwise operators to avoid too many variables:
    // encodedTiming = startTime + (endTime << 32) + (deferredDuration << 64)
    uint256 encodedTiming
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
      price: uint96(initialPrice),
      native: native,
      startTime: uint32(encodedTiming),
      endTime: uint32(encodedTiming >> 32),
      deferredDuration: uint32(encodedTiming >> 64),
      bidAt: 0,
      bidder: address(0)
    });
    emit ItemForAuction(
      tokenAddress,
      tokenId,
      initialPrice,
      native,
      uint32(encodedTiming),
      uint32(encodedTiming >> 32),
      uint32(encodedTiming >> 64)
    );
  }

  function setItemsForAuction(
    address[] calldata tokenAddresses,
    uint256[] calldata tokenIds,
    uint256[] calldata initialPrices,
    bool[] calldata natives,
    uint256[] calldata encodedTimings
  ) external virtual onlyOwner {
    if (
      tokenAddresses.length != tokenIds.length ||
      tokenAddresses.length != initialPrices.length ||
      tokenAddresses.length != natives.length ||
      tokenAddresses.length != encodedTimings.length
    ) {
      revert InvalidInput();
    }
    for (uint256 i = 0; i < tokenAddresses.length; i++) {
      setItemForAuction(tokenAddresses[i], tokenIds[i], initialPrices[i], natives[i], encodedTimings[i]);
    }
  }

  function getNextPrice(address tokenAddress, uint256 tokenId) public view virtual returns (uint256) {
    uint256 price = _items[tokenAddress][tokenId].price;
    if (_items[tokenAddress][tokenId].bidder != address(0)) {
      price += price / 10;
    }
    return price;
  }

  function getNextPriceBatch(address[] memory tokenAddresses, uint256[] memory tokenIds) public view virtual returns (uint256) {
    if (tokenAddresses.length != tokenIds.length) {
      revert InvalidInput();
    }
    uint256 totalPrice = 0;
    bool isNative = _items[tokenAddresses[0]][tokenIds[0]].native;
    for (uint256 i = 0; i < tokenAddresses.length; i++) {
      address tokenAddress = tokenAddresses[i];
      uint256 tokenId = tokenIds[i];

      if (i > 0 && isNative != _items[tokenAddress][tokenId].native) {
        revert ItemPriceTypeNotIdentical(); //can only sum one type of price
      }
      uint256 price = _items[tokenAddress][tokenId].price;
      if (_items[tokenAddress][tokenId].bidder != address(0)) {
        totalPrice += (price + price / 10);
      } else {
        totalPrice += price;
      }
    }
    return totalPrice;
  }

  function getFee(address tokenAddress, uint256 tokenId) public view virtual returns (uint256) {
    uint256 price = _items[tokenAddress][tokenId].price;
    if (_items[tokenAddress][tokenId].bidder != address(0)) {
      price += price / 10;
      return (price * 5) / 110;
    } else {
      return price;
    }
  }

  function auctionEndTime(address tokenAddress, uint256 tokenId) public view virtual returns (uint256) {
    Item storage item = _items[tokenAddress][tokenId];
    uint256 endTime = item.endTime;
    if (item.bidAt > 0 && (item.bidAt > endTime || endTime - item.bidAt < item.deferredDuration)) {
      endTime = item.bidAt + item.deferredDuration;
    }
    return endTime;
  }

  function isAuctionOver(address tokenAddress, uint256 tokenId) public view virtual returns (bool) {
    return block.timestamp > auctionEndTime(tokenAddress, tokenId);
  }

  function bid(address tokenAddress, uint256 tokenId) external payable nonReentrant {
    _bid(tokenAddress, tokenId, 0);
  }

  function _bid(address tokenAddress, uint256 tokenId, uint256 expectedSpending) internal returns (bool) {
    Item storage _item = _items[tokenAddress][tokenId];
    if (_item.startTime > block.timestamp) revert AuctionNotStarted();
    Item memory oldItem = _item;
    if (PFPAsset(tokenAddress).ownerOf(tokenId) != address(this)) {
      // the auction must own the asset
      if (expectedSpending == 0) revert AssetNotFound();
      // during batch we just skip the bid
      else return false;
    }
    if (isAuctionOver(tokenAddress, tokenId)) {
      if (expectedSpending == 0) revert AuctionIsOver();
      else return false;
    }
    uint256 price = getNextPrice(tokenAddress, tokenId);
    uint256 fee = getFee(tokenAddress, tokenId);
    _item.price = uint96(price);
    _item.bidAt = uint32(block.timestamp);
    _item.bidder = _msgSender();
    if (_item.native) {
      nativeFees += fee;
    } else {
      lfgFees += fee;
    }
    if (_item.native) {
      uint256 value = expectedSpending > 0 ? expectedSpending : msg.value;
      if (value < price) {
        if (expectedSpending == 0) revert InsufficientFunds();
        // during batch we just skip the bid
        else {
          // we prefer to revert the change than setting the values after the external calls
          // to avoid potential reentrancy issues
          _item.price = oldItem.price;
          _item.bidAt = oldItem.bidAt;
          _item.bidder = oldItem.bidder;
          nativeFees -= fee;
          return false;
        }
      } else {
        // The user may send more than the current price to be sure that
        // the transaction will not fail if the price has increased in the meantime.
        // If there is a surplus (during single bid) we send it back to the user:
        (bool success, ) = _msgSender().call{value: value - price}("");
        if (!success) revert UnableToTransferFunds();
        // ^ In this case we reverts to try to anticipate further issues later
      }
      if (oldItem.bidder != address(0)) {
        // Not the first bid.
        (bool success, ) = oldItem.bidder.call{value: price - fee}("");
        if (!success) {
          // ^ We ignore failures. If not, a bidder can use a smart contract to make a bid without
          // implementing a receive function. That would cause the call to fail, making impossible
          // for any other to make a bid over the asset
        }
      }
    } else {
      // If the user approves more than strictly required, they can be able to make a
      // successful bid even if the price has increased in the meantime.
      if (LFGToken(_lfg).balanceOf(_msgSender()) < price) {
        if (expectedSpending == 0) revert InsufficientFunds();
        // during batch we just skip the bid
        else {
          // we prefer to revert the change than setting the values after the external calls
          // to avoid potential reentrancy issues
          _item.price = oldItem.price;
          _item.bidAt = oldItem.bidAt;
          _item.bidder = oldItem.bidder;
          lfgFees -= fee;
          return false;
        }
      }
      LFGToken(_lfg).safeTransferFrom(_msgSender(), address(this), price);
      if (oldItem.bidder != address(0)) {
        // Not the first bid.
        LFGToken(_lfg).transfer(oldItem.bidder, price - fee);
        // ^ We use transfer to ignore the failure for the same reasons as above
      }
    }
    emit Bid(
      tokenAddress,
      tokenId,
      price,
      block.timestamp,
      _msgSender(),
      auctionEndTime(tokenAddress, tokenId),
      oldItem.bidder == address(0) ? 0 : oldItem.price,
      oldItem.bidder,
      price - fee
    );
    return true;
  }

  function bidBatch(
    address[] memory tokenAddresses,
    uint256[] memory tokenIds,
    uint256[] memory expectedSpendings
  ) external payable nonReentrant {
    if (tokenAddresses.length != tokenIds.length || tokenAddresses.length != expectedSpendings.length) {
      revert InvalidInput();
    }
    uint256 remaining = msg.value;
    for (uint256 i = 0; i < tokenAddresses.length; i++) {
      // avoiding double bidding, which would break the way
      // getNextPriceBatch is built
      if (_checked[tokenAddresses[i]][tokenIds[i]]) {
        revert CannotBatchBidSameItemTwice();
      }

      // the expected spending must be > 0 during batch bidding
      if (expectedSpendings[i] == 0) continue;
      uint256 expectedSpending = expectedSpendings[i];
      if (_items[tokenAddresses[i]][tokenIds[i]].native && expectedSpending > remaining) {
        // most likely it will fail later
        expectedSpending = remaining;
      }
      if (_bid(tokenAddresses[i], tokenIds[i], expectedSpending)) {
        if (_items[tokenAddresses[i]][tokenIds[i]].native) {
          remaining -= expectedSpending;
        }
      } else {
        emit BidFailed(tokenAddresses[i], tokenIds[i], _items[tokenAddresses[i]][tokenIds[i]].price, _msgSender());
      }
      _checked[tokenAddresses[i]][tokenIds[i]] = true;
    }
    // cleaning up
    for (uint256 i = 0; i < tokenAddresses.length; i++) {
      delete _checked[tokenAddresses[i]][tokenIds[i]];
    }

    // if there are unused funds, we refund them
    if (remaining > 0) {
      // all funds used. Refunding the remaining
      (bool success, ) = _msgSender().call{value: remaining}("");
      if (!success) revert UnableToTransferFunds();
    }
  }

  function claim(address tokenAddress, uint256 tokenId) external nonReentrant {
    Item memory _item = _items[tokenAddress][tokenId];
    if (!isAuctionOver(tokenAddress, tokenId)) revert AuctionIsNotOver();
    if (_item.bidder != _msgSender()) revert NotTheWinner();
    PFPAsset(tokenAddress).safeTransferFrom(address(this), _item.bidder, tokenId);
    emit Claim(tokenAddress, tokenId, _item.bidder, _item.price);
  }

  function withdrawProceeds(address beneficiary, bool native, uint256 amount) external virtual onlyOwner nonReentrant {
    if (beneficiary == address(0)) revert ZeroAddress();
    if (native) {
      if (amount == 0) {
        amount = nativeFees;
      }
      if (amount > nativeFees) revert InsufficientFees();
      // this should never happen and nativeFees should always be equal or smaller than the contract balance
      if (amount > address(this).balance) revert InsufficientFunds();
      nativeFees -= amount;
      (bool success, ) = beneficiary.call{value: amount}("");
      if (!success) revert UnableToTransferFunds();
    } else {
      uint256 balance = LFGToken(_lfg).balanceOf(address(this));
      if (amount == 0) {
        amount = lfgFees;
      }
      if (amount > lfgFees) revert InsufficientFees();
      // as for the native currency, this should never happen
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
