// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {AddressUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {ValidatableUpgradeable} from "../utils/ValidatableUpgradeable.sol";
import {LFGToken} from "../token/LFGToken.sol";
import {MemeNft} from "../meme/MemeNft.sol";

contract MemeFactory is Initializable, ValidatableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
  using SafeERC20Upgradeable for LFGToken;

  error MemeClubNotFound();
  error MemeClubIsLocked();
  error MemeClubPriceArgs();
  error MemeClubTooMany();
  error MemeClubLFGUnsupported();
  error InvalidAmount();
  error InvalidFunds();
  error InsufficientFunds();
  error InsufficientLFG();
  error UnableToSendFunds();
  
  event LfgTokenUpdate(address lfgToken_);
  event MemeClubCreated(uint256 callId, uint256 clubId, address nftAddress);
  event MemeClubTrade(uint256 clubId, uint256 tokenId, bool isBuy, uint256 supply);

  enum PriceFormulaType {
    Min,
    QuadCurve     // (supply+1)^2 / A
  }

  struct PriceFormulaArgs {
    uint256 quadCurveA;
  }

  struct MemeClub {
    uint256 clubId;
    bool isNative;      // native or $LFG
    bool isLocked;
    address nftAddress;
    address memeAddress;
    uint256 supply;
    uint256 funds;
    PriceFormulaType priceType;
    PriceFormulaArgs priceArgs; 
  }

  uint256 public baseClubId;
  LFGToken public lfgToken;
  
  // used to avoid double sell during batch sell
  mapping(uint256 => bool) private _checked;

  mapping(uint256 => MemeClub) public memeClubs;

  function initialize(
    address[] memory validators_
  ) public initializer {
    __Validatable_init();
    __Pausable_init();
    for (uint256 i = 0; i < validators_.length; i++) {
      updateValidator(validators_[i], true);
    }
  }

  function setLFGToken(address lfgToken_) public onlyOwner {
    lfgToken = LFGToken(lfgToken_);
    emit LfgTokenUpdate(lfgToken_);
  }

  function checkPriceFormulaArgs(PriceFormulaType priceType_, PriceFormulaArgs memory priceArgs_) public pure returns(bool) {
    if (priceType_ == PriceFormulaType.QuadCurve) {
      if (priceArgs_.quadCurveA <= 0) return false;
    } else {
      return false;
    }
    return true;
  }

  function _nextClubId() internal returns(uint256) {
    uint256 max = 1000000;
    ++baseClubId;
    if (baseClubId >= max) revert MemeClubTooMany(); 
    return block.chainid * max + baseClubId;
  }

  function newMemeClub( 
    uint256 callId,
    string memory name_,
    string memory symbol_,
    string memory tokenUri_,
    bool isNative_,
    PriceFormulaType priceType_, 
    PriceFormulaArgs memory priceArgs_
  ) external onlyOwner whenNotPaused nonReentrant {
    if (!isNative_ && address(lfgToken) == address(0)) revert MemeClubLFGUnsupported();
    if (!checkPriceFormulaArgs(priceType_, priceArgs_)) revert MemeClubPriceArgs();
    uint256 clubId = _nextClubId();
    MemeNft nft = new MemeNft(name_, symbol_, tokenUri_);
    memeClubs[clubId] = MemeClub({
      clubId: clubId,
      isNative: isNative_,
      isLocked: false,
      nftAddress: address(nft),
      memeAddress: address(0),
      supply: 0,
      funds: 0,
      priceType: priceType_,
      priceArgs: priceArgs_
    });
    emit MemeClubCreated(callId, clubId, address(nft));
  }

  function getPrice(
    uint256 supply, 
    PriceFormulaType priceType,
    PriceFormulaArgs memory priceArgs,
    uint256 amount
  ) public pure returns(uint256) { 
    uint256 price = 0;
    if (priceType == PriceFormulaType.QuadCurve) {
      for (uint256 i = 0; i < amount; i++) {
        uint256 quadCurveA = priceArgs.quadCurveA;
        price += (price + 1 + i) * (supply + 1 + i) * 1 ether / quadCurveA;
      }
    } 
    return price;
  }

  function getBuyPrice(uint256 clubId, uint256 amount)  public view returns(uint256) {
    uint256 supply = memeClubs[clubId].supply;
    PriceFormulaType priceType = memeClubs[clubId].priceType;
    PriceFormulaArgs memory priceArgs = memeClubs[clubId].priceArgs;
    uint256 price = getPrice(supply, priceType, priceArgs, amount);
    return price;
  }

  function getSellPrice(uint256 clubId, uint256 amount) public view returns(uint256) {
    uint256 supply = memeClubs[clubId].supply;
    PriceFormulaType priceType = memeClubs[clubId].priceType;
    PriceFormulaArgs memory priceArgs = memeClubs[clubId].priceArgs;
    uint256 price = getPrice(supply, priceType, priceArgs, supply - amount);
    return price;
  }

  function buyCard(uint256 clubId, uint256 amount, uint256 expectedPrice) external payable onlyOwner whenNotPaused nonReentrant {
    if (amount == 0) revert InvalidAmount();
    MemeClub storage club = memeClubs[clubId];
    if (club.nftAddress == address(0)) revert MemeClubNotFound();
    if (club.isLocked) revert MemeClubIsLocked();

    uint256 actualPrice = getBuyPrice(clubId, amount);
    if (club.isNative) {
      if (actualPrice > msg.value) revert InsufficientFunds();
      _sendNativeFunds(msg.value - actualPrice);
    } else {    // $LFG
      if (msg.value != 0) revert InvalidFunds();
      if (actualPrice > expectedPrice) revert InsufficientFunds();
      if (lfgToken.balanceOf(_msgSender()) < actualPrice) revert InsufficientLFG();
      lfgToken.safeTransferFrom(_msgSender(), address(this), actualPrice);
    }

    MemeNft nft = MemeNft(club.nftAddress);
    nft.safeMint(_msgSender(), amount);
    uint256 lastTokenId = nft.lastTokenId();
    for (uint256 i = 0; i < amount; i++) {
      uint256 tokenId = lastTokenId - amount + 1; 
      emit MemeClubTrade(clubId, tokenId, true, club.supply + i + 1);
    }

    club.funds += actualPrice;
    club.supply += amount;
  }

  function sellCard(uint256 clubId, uint256[] memory tokenIds) external onlyOwner whenNotPaused nonReentrant {
    if (tokenIds.length == 0) revert InvalidAmount();
    MemeClub storage club = memeClubs[clubId];
    if (club.nftAddress == address(0)) revert MemeClubNotFound();
    if (club.isLocked) revert MemeClubIsLocked();
 
    uint256 amount = 0;
    for (uint256 i = 0; i < tokenIds.length; i++) {
      uint256 tokenId = tokenIds[i];
      if (MemeNft(club.nftAddress).ownerOf(tokenId) != _msgSender()) {
        if (!_checked[tokenId]) {
          amount++;
          _checked[tokenId] = true;
        }
      }
    }
    
    if (amount == 0) revert InvalidAmount();
    uint256 actualPrice = getSellPrice(clubId, amount);
    if (club.isNative) {
      _sendNativeFunds(actualPrice);
    } else {  // $LFG
      lfgToken.safeTransferFrom(address(this), _msgSender(), actualPrice);
    }

    club.funds -= actualPrice;
    club.supply -= amount;

    for (uint256 i = tokenIds.length - 1; i >= 0; i++) {
      emit MemeClubTrade(clubId, tokenIds[i], false, club.supply + i);
      delete _checked[tokenIds[i]]; 
    }
  }
 
  function _sendNativeFunds(uint256 amount) internal {
    if (amount > 0) {
      (bool success,) = _msgSender().call{value: amount}("");
      if (!success) revert UnableToSendFunds();
    }
  }

  function pause() external onlyOwner {
    _pause();
  }

  function unpause() external onlyOwner {
    _unpause();
  }

}