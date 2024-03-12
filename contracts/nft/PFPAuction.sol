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
  event BidFailed(
    address indexed tokenAddress,
    uint256 indexed tokenId,
    uint256 price,
    address indexed bidder,
    BidError _error
  );

  error UnableToTransferFunds();
  error ZeroAddress();
  error InsufficientFunds();
  error InsufficientAllowance();
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
  error ExcessiveSlippage(uint256 slippage);

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

  enum BidError {
    None,
    AuctionNotStarted,
    AssetNotFound,
    AuctionIsOver,
    ExcessiveSlippage,
    InsufficientFunds,
    InvalidExpectedPrice,
    InsufficientAllowance
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

  function getLastPrice(address tokenAddress, uint256 tokenId) public view virtual returns (uint256) {
    return _items[tokenAddress][tokenId].price;
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

  function _canBid(
    address tokenAddress,
    uint256 tokenId,
    uint256 expectedPrice,
    uint256 slippage
  ) internal view returns (BidError, uint256) {
    Item storage _item = _items[tokenAddress][tokenId];
    uint256 price = getNextPrice(tokenAddress, tokenId);
    if (_item.startTime > block.timestamp) {
      return (BidError.AuctionNotStarted, price);
    }
    if (PFPAsset(tokenAddress).ownerOf(tokenId) != address(this)) {
      return (BidError.AssetNotFound, price);
    }
    if (isAuctionOver(tokenAddress, tokenId)) {
      return (BidError.AuctionIsOver, price);
    }
    if (expectedPrice == 0) {
      return (BidError.InvalidExpectedPrice, price);
    }
    uint256 _slippage;
    if (price > expectedPrice) {
      _slippage = (100 * (price - expectedPrice)) / expectedPrice;
    }
    if (_slippage > slippage) {
      return (BidError.ExcessiveSlippage, price);
    }
    return (BidError.None, price);
  }

  function _bid(address tokenAddress, uint256 tokenId, uint256 price, uint256 remainingValue) internal returns (BidError) {
    Item storage _item = _items[tokenAddress][tokenId];
    Item memory oldItem = _item;
    uint256 fee = getFee(tokenAddress, tokenId);
    if (_item.native) {
      if (remainingValue < price) {
        return BidError.InsufficientFunds;
      }
      nativeFees += fee;
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
      if (_lfg.balanceOf(_msgSender()) < price) {
        return BidError.InsufficientFunds;
      }
      if (_lfg.allowance(_msgSender(), address(this)) < price) {
        return BidError.InsufficientAllowance;
      }
      lfgFees += fee;
      _lfg.safeTransferFrom(_msgSender(), address(this), price);
      if (oldItem.bidder != address(0)) {
        // Not the first bid.
        _lfg.transfer(oldItem.bidder, price - fee);
        // ^ We use transfer to ignore the failure for the same reasons as above
      }
    }
    _item.bidder = _msgSender();
    _item.bidAt = uint32(block.timestamp);
    _item.price = uint96(price);
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
    return BidError.None;
  }

  function bid(address tokenAddress, uint256 tokenId, uint256 expectedPrice, uint256 slippage) external payable nonReentrant {
    address[] memory tokenAddresses = new address[](1);
    tokenAddresses[0] = tokenAddress;
    uint256[] memory tokenIds = new uint256[](1);
    tokenIds[0] = tokenId;
    uint256[] memory expectedPrices = new uint256[](1);
    expectedPrices[0] = expectedPrice;
    _bidBatch(tokenAddresses, tokenIds, expectedPrices, slippage);
  }

  function bidBatch(
    address[] memory tokenAddresses,
    uint256[] memory tokenIds,
    uint256[] memory expectedPrices,
    uint256 slippage
  ) external payable nonReentrant {
    _bidBatch(tokenAddresses, tokenIds, expectedPrices, slippage);
  }

  function _bidBatch(
    address[] memory tokenAddresses,
    uint256[] memory tokenIds,
    uint256[] memory expectedPrices,
    uint256 slippage
  ) internal {
    if (tokenAddresses.length != tokenIds.length || tokenAddresses.length != expectedPrices.length) {
      revert InvalidInput();
    }
    uint256 remainingValue = msg.value;
    for (uint256 i = 0; i < tokenAddresses.length; i++) {
      uint256 expectedPrice = expectedPrices[i];

      // avoiding double bidding
      if (_checked[tokenAddresses[i]][tokenIds[i]]) {
        delete _checked[tokenAddresses[i]][tokenIds[i]];
        revert CannotBatchBidSameItemTwice();
      }
      _checked[tokenAddresses[i]][tokenIds[i]] = true;

      (BidError _error, uint256 _price) = _canBid(tokenAddresses[i], tokenIds[i], expectedPrice, slippage);
      if (_error == BidError.None) {
        _error = _bid(tokenAddresses[i], tokenIds[i], _price, remainingValue);
      }
      if (_error == BidError.None) {
        if (_items[tokenAddresses[i]][tokenIds[i]].native) {
          remainingValue -= _price;
        }
      } else {
        emit BidFailed(tokenAddresses[i], tokenIds[i], _price, _msgSender(), _error);
      }
    }
    // cleaning up
    for (uint256 i = 0; i < tokenAddresses.length; i++) {
      delete _checked[tokenAddresses[i]][tokenIds[i]];
    }
    // if there are unused funds, we refund them
    if (remainingValue > 0) {
      // all funds used. Refunding the remaining
      (bool success, ) = _msgSender().call{value: remainingValue}("");
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
      uint256 balance = _lfg.balanceOf(address(this));
      if (amount == 0) {
        amount = lfgFees;
      }
      if (amount > lfgFees) revert InsufficientFees();
      // as for the native currency, this should never happen
      if (amount > balance) revert InsufficientFunds();
      lfgFees -= amount;
      _lfg.safeTransfer(beneficiary, amount);
    }
  }

  function burnLfgProceeds(uint256 amount) external virtual onlyOwner nonReentrant {
    uint256 balance = _lfg.balanceOf(address(this));
    if (amount == 0) {
      amount = lfgFees;
    }
    if (amount > balance) revert InsufficientFunds();
    lfgFees -= amount;
    _lfg.burn(amount);
  }
}
