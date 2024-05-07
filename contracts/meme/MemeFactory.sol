// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {ValidatableUpgradeable} from "../utils/ValidatableUpgradeable.sol";
import {LFGToken} from "../token/LFGToken.sol";
import {Meme404} from "./Meme404.sol";
import {Meme404Proxy} from "./Meme404Proxy.sol";
import {MemeFT} from "./MemeFT.sol";

contract MemeFactory is Initializable, ValidatableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
  using SafeERC20Upgradeable for LFGToken;

  error ZeroAmount();
  error ZeroAddress();
  error MemeClubNotFound();
  error MemeClubIsLocked();
  error MemeClubPriceTypeUnsupported();
  error MemeClubPriceArgs();
  error MemeClubTooMany();
  error MemeClubLFGUnsupported();
  error MemeClubUnlocked();
  error MemeTokenNewDuplidate();
  error MemeTokenNotCreated();
  error InvalidAmount();
  error InvalidFunds();
  error InsufficientFunds();
  error InsufficientLFG();
  error UnableToSendFunds();
  error InsufficientFees();
  error UnableToTransferFunds();
  error SignatureExpired();
  error SignatureAlreadyUsed();

  event LfgTokenUpdate(address lfgToken_);
  event SubjectFeePercentUpdate(uint256 feePercent);
  event ProtocolFeePercentUpdate(uint256 feePercent);
  event ProtocolFeeDestinationUpdate(address feeDestination);
  event MemeClubCreated(uint256 callId, uint256 clubId, address creator);
  event MemeTokenCreated(uint256 callId, uint256 clubId, address creator);

  event MemeClubTrade(
    uint256 clubId,
    address trader,
    uint256 supply,
    bool isLocked,
    bool isBuy,
    uint256 tradeAmount,
    uint256 holdingAmount,
    uint256 priceAfterFee,
    uint256 protocolFee,
    uint256 subjectFee
  );

  event MemeTokenMint(uint256 callId, uint256 clubId, address minter, uint256 amount);

  enum PriceFormulaType {
    Min,
    Linear,
    QuadCurve, // (supply+1)^2 / A
    Fixed
  }

  struct PriceFormulaArgs {
    uint256 arg1;
    uint256 arg2;
  }

  struct MemeClub {
    uint256 clubId;
    uint256 maxSupply;
    bool isNative; // native or $LFG
    bool isFT; // 404 or ERC20
    bool isLocked;
    address subjectAddress;
    address memeAddress;
    uint256 supply;
    uint256 funds;
    PriceFormulaType priceType;
    PriceFormulaArgs priceArgs;
  }

  mapping(bytes32 => bool) private _usedSignatures;

  uint256 public baseClubId;
  LFGToken public lfgToken;

  // used to avoid double sell during batch sell
  mapping(uint256 => bool) private _checked;

  mapping(uint256 => MemeClub) public memeClubs;
  mapping(uint256 => mapping(address => uint256)) public balanceOf;

  address public protocolFeeDestination;
  uint256 public protocolFeePercent;
  uint256 public subjectFeePercent;
  uint256 public protocolLFGFees;
  uint256 public protocolNativeFees;

  address public memeImplementation;

  function initialize(
    address protocolFeeDestination_,
    address[] memory validators_,
    address memeImplementation_
  ) public initializer {
    __Validatable_init();
    __Pausable_init();
    for (uint256 i = 0; i < validators_.length; i++) {
      updateValidator(validators_[i], true);
    }
    setSubjectFeePercent(0 ether / 100);
    setProtocolFeePercent(5 ether / 100);
    setProtocolFeeDestination(protocolFeeDestination_);
    memeImplementation = memeImplementation_;
  }

  function setLFGToken(address lfgToken_) public onlyOwner {
    lfgToken = LFGToken(lfgToken_);
    emit LfgTokenUpdate(lfgToken_);
  }

  function setSubjectFeePercent(uint256 feePercent_) public virtual onlyOwner {
    subjectFeePercent = feePercent_;
    emit SubjectFeePercentUpdate(subjectFeePercent);
  }

  function setProtocolFeePercent(uint256 feePercent_) public virtual onlyOwner {
    protocolFeePercent = feePercent_;
    emit ProtocolFeePercentUpdate(protocolFeePercent);
  }

  function setProtocolFeeDestination(address feeDestination_) public virtual onlyOwner {
    protocolFeeDestination = feeDestination_;
    emit ProtocolFeeDestinationUpdate(protocolFeeDestination);
  }

  function _nextClubId() internal returns (uint256) {
    uint256 max = 10000000;
    ++baseClubId;
    if (baseClubId >= max) revert MemeClubTooMany();
    return block.chainid * max + baseClubId;
  }

  function getMemeClub(uint256 clubId) public view returns (MemeClub memory) {
    return memeClubs[clubId];
  }

  function getSupply(uint256 clubId) public view returns (uint256) {
    return memeClubs[clubId].supply;
  }

  function getBalanceOf(uint256 clubId, address user) public view returns (uint256) {
    return balanceOf[clubId][user];
  }

  function isValidPriceType(uint256 priceType) public pure returns (bool) {
    return priceType == uint256(PriceFormulaType.Linear)
      || priceType == uint256(PriceFormulaType.QuadCurve)
      || priceType == uint256(PriceFormulaType.Fixed);
  }

  function newMemeClub(
    uint256 callId_,
    uint256 maxSupply_,
    bool isNative_,
    bool isFT_,
    uint256 priceType_,
    uint256 priceArg1_,
    uint256 priceArg2_,
    bytes calldata signature
  ) external whenNotPaused nonReentrant {
    _validateSignature(block.timestamp, 0, hashForNewMemeClub(callId_, maxSupply_, isNative_, _msgSender()), signature);

    if (!isNative_ && address(lfgToken) == address(0)) revert MemeClubLFGUnsupported();
    if (!isValidPriceType(priceType_)) revert MemeClubPriceTypeUnsupported();

    uint256 clubId = _nextClubId();
    memeClubs[clubId] = MemeClub({
      clubId: clubId,
      maxSupply: maxSupply_,
      isNative: isNative_,
      isFT: isFT_,
      isLocked: false,
      subjectAddress: _msgSender(),
      memeAddress: address(0),
      supply: 0,
      funds: 0,
      priceType: PriceFormulaType(priceType_),
      priceArgs: PriceFormulaArgs({arg1: priceArg1_, arg2: priceArg2_})
    });

    emit MemeClubCreated(callId_, clubId, _msgSender());
  }

  function newMemeToken(
    uint256 callId,
    uint256 clubId,
    string calldata name,
    string calldata symbol,
    string calldata baseURI,
    uint256 baseUnit,
    bytes calldata signature
  ) external whenNotPaused nonReentrant {
    bytes32 hashValue = hashForNewMeme404(callId, clubId, _msgSender(), name, symbol, baseURI, baseUnit);
    _validateSignature(block.timestamp, 0, hashValue, signature);
    MemeClub storage club = memeClubs[clubId];
    if (club.clubId == 0) revert MemeClubNotFound();
    if (!club.isLocked) revert MemeClubUnlocked();
    if (club.memeAddress != address(0)) revert MemeTokenNewDuplidate();
    
    if (club.isFT) {
      MemeFT meme = new MemeFT(name, symbol);
      club.memeAddress = address(meme);
    } else {
      Meme404Proxy memeProxy = new Meme404Proxy(memeImplementation);
      Meme404 meme = Meme404(payable(address(memeProxy)));
      meme.init(name, symbol, baseURI, baseUnit, 0, address(this));
      club.memeAddress = address(meme);
    }

    emit MemeTokenCreated(callId, clubId, _msgSender());
  }

  function mintMemeToken(
    uint256 callId,
    uint256 clubId,
    uint256 amount,
    uint256 timestamp,
    uint256 validFor,
    bytes calldata signature
  ) external payable whenNotPaused nonReentrant {
    _validateSignature(
      timestamp,
      validFor,
      hashForMintMeme404(callId, clubId, _msgSender(), amount, timestamp, validFor),
      signature
    );
    if (amount == 0) revert ZeroAmount();
    MemeClub storage club = memeClubs[clubId];
    if (club.memeAddress == address(0)) revert MemeTokenNotCreated();
    if (club.isFT) {
      MemeFT meme = MemeFT(payable(club.memeAddress));
      meme.mint(_msgSender(), amount);
    } else {
      Meme404 meme = Meme404(payable(club.memeAddress));
      meme.mint(_msgSender(), amount);
    }

    emit MemeTokenMint(callId, clubId, _msgSender(), amount);
  }

  function getPrice(
    uint256 supply,
    uint256 amount,
    PriceFormulaType priceType,
    uint256 priceArg1,
    uint256 priceArg2
  ) public pure returns (uint256) {
    uint256 price = 0;
    if (priceType == PriceFormulaType.Linear) {
      uint256 sum1 = (supply * (supply + 1)) / 2 * priceArg1;
      uint256 sum2 = ((supply + amount) * (supply + amount + 1)) / 2 * priceArg1 + (supply + amount) * priceArg2;
      price = sum2 - sum1;
    } else if (priceType == PriceFormulaType.QuadCurve) {
      uint256 sum1 = (supply * (supply + 1) * (2 * supply + 1)) / 6 * priceArg1 + (supply * (supply + 1) / 2) * priceArg2;
      uint256 sum2 = ((supply + amount) * (supply + amount + 1) * (2 * (supply + amount) + 1)) / 6 * priceArg1 + ((supply + amount) * (supply + 1 + amount) / 2) * priceArg2;
      price = sum2 - sum1;
    } else if (priceType == PriceFormulaType.Fixed) {
      price = amount * priceArg1;
    }
    return price;
  }

  function getProtocolFee(uint256 price) public view virtual returns (uint256) {
    return (price * protocolFeePercent) / 1 ether;
  }

  function getSubjectFee(uint256 price) public view virtual returns (uint256) {
    return (price * subjectFeePercent) / 1 ether;
  }

  function getBuyPrice(uint256 clubId, uint256 amount) public view returns (uint256) {
    uint256 supply = memeClubs[clubId].supply;
    PriceFormulaType priceType = memeClubs[clubId].priceType;
    PriceFormulaArgs memory priceArgs = memeClubs[clubId].priceArgs;
    uint256 price = getPrice(supply, amount, priceType, priceArgs.arg1, priceArgs.arg2);
    return price;
  }

  function getBuyPriceAfterFee(uint256 clubId, uint256 amount) public view returns (uint256) {
    uint256 supply = memeClubs[clubId].supply;
    PriceFormulaType priceType = memeClubs[clubId].priceType;
    PriceFormulaArgs memory priceArgs = memeClubs[clubId].priceArgs;
    uint256 price = getPrice(supply, amount, priceType, priceArgs.arg1, priceArgs.arg2);
    uint256 protocolFee = getProtocolFee(price);
    uint256 subjectFee = getSubjectFee(price);
    return price + protocolFee + subjectFee;
  }

  function getSellPrice(uint256 clubId, uint256 amount) public view returns (uint256) {
    uint256 supply = memeClubs[clubId].supply;
    PriceFormulaType priceType = memeClubs[clubId].priceType;
    PriceFormulaArgs memory priceArgs = memeClubs[clubId].priceArgs;
    uint256 price = getPrice(supply - amount, amount, priceType, priceArgs.arg1, priceArgs.arg2);
    uint256 protocolFee = getProtocolFee(price);
    uint256 subjectFee = getSubjectFee(price);
    return price - protocolFee - subjectFee;
  }

  function buyCard(uint256 clubId, uint256 amount, uint256 expectedPrice) external payable whenNotPaused nonReentrant {
    if (amount == 0) revert InvalidAmount();
    MemeClub storage club = memeClubs[clubId];
    if (club.isLocked) revert MemeClubIsLocked();

    uint256 actualPrice = getBuyPrice(clubId, amount);
    uint256 protocolFee = getProtocolFee(actualPrice);
    uint256 subjectFee = getSubjectFee(actualPrice);
    uint256 priceAfterFee = actualPrice + protocolFee + subjectFee;
    if (club.isNative) {
      if (priceAfterFee > msg.value) revert InsufficientFunds();
      _sendNativeFunds(_msgSender(), msg.value - priceAfterFee);
      _sendNativeFunds(club.subjectAddress, subjectFee);
      protocolNativeFees += protocolFee;
    } else {
      // $LFG
      if (msg.value != 0) revert InvalidFunds();
      if (priceAfterFee > expectedPrice) revert InsufficientFunds();
      if (lfgToken.balanceOf(_msgSender()) < priceAfterFee) revert InsufficientLFG();
      lfgToken.safeTransferFrom(_msgSender(), address(this), priceAfterFee);
      lfgToken.transfer(club.subjectAddress, subjectFee);
      protocolLFGFees += protocolFee;
    }

    club.funds += actualPrice;
    club.supply += amount;
    if (club.maxSupply <= club.supply) {
      club.isLocked = true;
    }

    uint256 holdingAmount = balanceOf[clubId][_msgSender()];
    balanceOf[clubId][_msgSender()] = holdingAmount + amount;

    emit MemeClubTrade(
      clubId,
      _msgSender(),
      club.supply,
      club.isLocked,
      true,
      amount,
      holdingAmount + amount,
      priceAfterFee,
      protocolFee,
      subjectFee
    );
  }

  function sellCard(uint256 clubId, uint256 amount) external whenNotPaused nonReentrant {
    if (amount == 0) revert InvalidAmount();
    MemeClub storage club = memeClubs[clubId];
    if (club.isLocked) revert MemeClubIsLocked();

    uint256 holdingAmount = balanceOf[clubId][_msgSender()];
    if (amount > holdingAmount) revert InvalidAmount();

    uint256 actualPrice = getSellPrice(clubId, amount);
    uint256 protocolFee = getProtocolFee(actualPrice);
    uint256 subjectFee = getSubjectFee(actualPrice);
    uint256 priceAfterFee = actualPrice - protocolFee - subjectFee;
    if (club.isNative) {
      _sendNativeFunds(_msgSender(), priceAfterFee);
      _sendNativeFunds(club.subjectAddress, subjectFee);
      protocolNativeFees += protocolFee;
    } else {
      // $LFG
      lfgToken.transfer(_msgSender(), priceAfterFee);
      lfgToken.transfer(club.subjectAddress, subjectFee);
      protocolLFGFees += protocolFee;
    }

    club.funds -= actualPrice;
    club.supply -= amount;
    balanceOf[clubId][_msgSender()] = holdingAmount - amount;

    emit MemeClubTrade(
      clubId,
      _msgSender(),
      club.supply,
      club.isLocked,
      true,
      amount,
      holdingAmount - amount,
      priceAfterFee,
      protocolFee,
      subjectFee
    );
  }

  function _sendNativeFunds(address beneficiary, uint256 amount) internal {
    if (beneficiary != address(0) && amount > 0) {
      (bool success, ) = beneficiary.call{value: amount}("");
      if (!success) revert UnableToSendFunds();
    }
  }

  function withdrawProceeds(address beneficiary, bool native, uint256 amount) external virtual onlyOwner nonReentrant {
    if (beneficiary == address(0)) revert ZeroAddress();
    if (native) {
      if (amount == 0) {
        amount = protocolNativeFees;
      }
      if (amount > protocolNativeFees) revert InsufficientFees();
      // this should never happen and nativeFees should always be equal or smaller than the contract balance
      if (amount > address(this).balance) revert InsufficientFunds();
      protocolNativeFees -= amount;
      (bool success, ) = beneficiary.call{value: amount}("");
      if (!success) revert UnableToTransferFunds();
    } else {
      uint256 balance = lfgToken.balanceOf(address(this));
      if (amount == 0) {
        amount = protocolLFGFees;
      }
      if (amount > protocolLFGFees) revert InsufficientFees();
      // as for the native currency, this should never happen
      if (amount > balance) revert InsufficientFunds();
      protocolLFGFees -= amount;
      lfgToken.safeTransfer(beneficiary, amount);
    }
  }

  function pause() external onlyOwner {
    _pause();
  }

  function unpause() external onlyOwner {
    _unpause();
  }

  function _saveSignatureAsUsed(bytes memory _signature) internal {
    bytes32 key = bytes32(keccak256(abi.encodePacked(_signature)));
    if (_usedSignatures[key]) revert SignatureAlreadyUsed();
    _usedSignatures[key] = true;
  }

  function isSignatureUsed(bytes memory _signature) public view returns (bool) {
    bytes32 key = bytes32(keccak256(abi.encodePacked(_signature)));
    return _usedSignatures[key];
  }

  function _validateSignature(
    uint256 timestamp,
    uint256 validFor, // Usually fixed to 2 hours for apply
    bytes32 hash,
    bytes calldata signature
  ) internal {
    if (timestamp < block.timestamp - validFor) revert SignatureExpired();
    if (!signedByValidator(hash, signature)) revert InvalidSignature();
    _saveSignatureAsUsed(signature);
  }

  function hashForNewMemeClub(uint256 callId, uint256 maxSupply, bool isNative, address creator) public view returns (bytes32) {
    return keccak256(abi.encodePacked("\x19\x01", block.chainid, callId, maxSupply, isNative, creator));
  }

  function hashForNewMeme404(
    uint256 callId,
    uint256 clubId,
    address creator,
    string calldata name,
    string calldata symbol,
    string calldata baseURI,
    uint256 baseUnit
  ) public view returns (bytes32) {
    return keccak256(abi.encodePacked("\x19\x01", block.chainid, callId, clubId, creator, name, symbol, baseURI, baseUnit));
  }

  function hashForMintMeme404(
    uint256 callId,
    uint256 clubId,
    address applyer,
    uint256 amount,
    uint256 timestamp,
    uint256 validFor
  ) public view returns (bytes32) {
    return keccak256(abi.encodePacked("\x19\x01", block.chainid, callId, clubId, applyer, amount, timestamp, validFor));
  }
}
