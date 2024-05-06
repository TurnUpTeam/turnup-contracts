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

contract Meme404Factory is Initializable, ValidatableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
  using SafeERC20Upgradeable for LFGToken;

  error ZeroAmount();
  error ZeroAddress();
  error MemeClubNotFound();
  error MemeClubIsLocked();
  error MemeClubPriceArgs();
  error MemeClubTooMany();
  error MemeClubLFGUnsupported();
  error MemeClubUnlocked();
  error Meme404NewDuplicate();
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
  event Meme404Created(uint256 callId, uint256 clubId, address creator);

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

  event Meme404Mint(uint256 callId, uint256 clubId, address minter, uint256 amount);

  enum PriceFormulaType {
    Min,
    QuadCurve // (supply+1)^2 / A
  }

  struct PriceFormulaArgs {
    uint256 quadCurveA;
  }

  struct MemeClub {
    uint256 clubId;
    uint256 maxSupply;
    bool isNative; // native or $LFG
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
  address public mirrorImplementation;

  function initialize(
    address protocolFeeDestination_,
    address[] memory validators_,
    address memeImplementation_,
    address mirrorImplementation_
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
    mirrorImplementation = mirrorImplementation_;
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

  function newMemeClubWithQuadCurve(
    uint256 callId_,
    uint256 maxSupply_,
    bool isNative_,
    uint256 quadCurveA,
    bytes calldata signature
  ) external whenNotPaused nonReentrant {
    if (!isNative_ && address(lfgToken) == address(0)) revert MemeClubLFGUnsupported();
    // it cannot be negative
    if (quadCurveA == 0) revert MemeClubPriceArgs();

    _validateSignature(
      block.timestamp,
      0,
      hashForNewMemeClub(callId_, maxSupply_, isNative_, quadCurveA, _msgSender()),
      signature
    );

    uint256 clubId = _nextClubId();
    memeClubs[clubId] = MemeClub({
      clubId: clubId,
      maxSupply: maxSupply_,
      isNative: isNative_,
      isLocked: false,
      subjectAddress: _msgSender(),
      memeAddress: address(0),
      supply: 0,
      funds: 0,
      priceType: PriceFormulaType.QuadCurve,
      priceArgs: PriceFormulaArgs({quadCurveA: quadCurveA})
    });

    emit MemeClubCreated(callId_, clubId, _msgSender());
  }

  function newMeme404(
    uint256 callId,
    uint256 clubId,
    string calldata name,
    string calldata symbol,
    string calldata baseURI,
    uint256 baseUnit,
    bytes calldata signature
  ) external whenNotPaused nonReentrant {
    MemeClub storage club = memeClubs[clubId];
    if (club.clubId == 0) revert MemeClubNotFound();
    if (!club.isLocked) revert MemeClubUnlocked();
    if (club.memeAddress != address(0)) revert Meme404NewDuplicate();

    bytes32 hashValue = hashForNewMeme404(callId, clubId, _msgSender(), name, symbol, baseURI, baseUnit);
    _validateSignature(block.timestamp, 0, hashValue, signature);

    Meme404Proxy memeProxy = new Meme404Proxy(memeImplementation);
    Meme404 meme = Meme404(payable(address(memeProxy)));
    meme.init(name, symbol, baseURI, baseUnit, 0, address(this), mirrorImplementation);
    club.memeAddress = address(meme);

    emit Meme404Created(callId, clubId, _msgSender());
  }

  function mintMeme404(
    uint256 callId,
    uint256 clubId,
    uint256 amount,
    uint256 timestamp,
    uint256 validFor,
    bytes calldata signature
  ) external payable whenNotPaused nonReentrant {
    if (amount == 0) revert ZeroAmount();
    MemeClub storage club = memeClubs[clubId];
    if (club.memeAddress == address(0)) revert Meme404NewDuplicate();
    _validateSignature(
      timestamp,
      validFor,
      hashForMintMeme404(callId, clubId, _msgSender(), amount, timestamp, validFor),
      signature
    );
    Meme404 meme = Meme404(payable(club.memeAddress));
    meme.mint(_msgSender(), amount);

    emit Meme404Mint(callId, clubId, _msgSender(), amount);
  }

  function getPrice(
    uint256 supply,
    uint256 amount,
    PriceFormulaType priceType,
    PriceFormulaArgs memory priceArgs
  ) public pure returns (uint256) {
    uint256 price = 0;
    if (priceType == PriceFormulaType.QuadCurve) {
      for (uint256 i = 0; i < amount; i++) {
        uint256 quadCurveA = priceArgs.quadCurveA;
        price += ((supply + 1 + i) * (supply + 1 + i) * 1 ether) / quadCurveA;
      }
    }
    return price;
  }

  function getPriceByClubId(uint256 clubId, uint256 amount, bool sellingPrice) public view returns (uint256) {
    return
      getPrice(
        memeClubs[clubId].supply - (sellingPrice ? amount : 0),
        amount,
        memeClubs[clubId].priceType,
        memeClubs[clubId].priceArgs
      );
  }

  function getProtocolFee(uint256 price) public view virtual returns (uint256) {
    return (price * protocolFeePercent) / 1 ether;
  }

  function getSubjectFee(uint256 price) public view virtual returns (uint256) {
    return (price * subjectFeePercent) / 1 ether;
  }

  function getBuyPrice(uint256 clubId, uint256 amount) public view returns (uint256) {
    return getPriceByClubId(clubId, amount, false);
  }

  function getBuyPriceAfterFee(uint256 clubId, uint256 amount) public view returns (uint256) {
    uint256 price = getPriceByClubId(clubId, amount, false);
    uint256 protocolFee = getProtocolFee(price);
    uint256 subjectFee = getSubjectFee(price);
    return price + protocolFee + subjectFee;
  }

  // Should this be getSellPriceAfterFee instead?
  function getSellPrice(uint256 clubId, uint256 amount) public view returns (uint256) {
    uint256 price = getPriceByClubId(clubId, amount, true);
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
    } else {
      // $LFG
      if (msg.value != 0) revert InvalidFunds();
      if (priceAfterFee > expectedPrice) revert InsufficientFunds();
      if (lfgToken.balanceOf(_msgSender()) < priceAfterFee) revert InsufficientLFG();
    }

    club.funds += actualPrice;
    club.supply += amount;

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

    // we make the external calls at the end to minimize reentrancy risks
    if (club.isNative) {
      protocolNativeFees += protocolFee;
      _sendNativeFunds(_msgSender(), msg.value - priceAfterFee);
      _sendNativeFunds(club.subjectAddress, subjectFee);
    } else {
      protocolLFGFees += protocolFee;
      lfgToken.safeTransferFrom(_msgSender(), address(this), priceAfterFee);
      lfgToken.transfer(club.subjectAddress, subjectFee);
    }
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

    // we make the external calls at the end to minimize reentrancy risks
    if (club.isNative) {
      protocolNativeFees += protocolFee;
      _sendNativeFunds(_msgSender(), priceAfterFee);
      _sendNativeFunds(club.subjectAddress, subjectFee);
    } else {
      // $LFG
      protocolLFGFees += protocolFee;
      lfgToken.transfer(_msgSender(), priceAfterFee);
      lfgToken.transfer(club.subjectAddress, subjectFee);
    }
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
    bytes32 key = _hashBytes(_signature);
    if (_usedSignatures[key]) revert SignatureAlreadyUsed();
    _usedSignatures[key] = true;
  }

  function isSignatureUsed(bytes memory _signature) public view returns (bool) {
    bytes32 key = _hashBytes(_signature);
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

  function hashForNewMemeClub(
    uint256 callId,
    uint256 maxSupply,
    bool isNative,
    uint256 quadCurveA,
    address creator
  ) public view returns (bytes32) {
    // we use abi.encode instead of abi.encodePacked to avoid that the series
    // block.chainid, callId, maxSupply risks to generate a collision,
    // despite being more expensive
    return keccak256(abi.encode("\x19\x01", block.chainid, callId, maxSupply, isNative, quadCurveA, creator));
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
    return keccak256(abi.encode("\x19\x01", block.chainid, callId, clubId, creator, name, symbol, baseURI, baseUnit));
  }

  function hashForMintMeme404(
    uint256 callId,
    uint256 clubId,
    address applyer,
    uint256 amount,
    uint256 timestamp,
    uint256 validFor
  ) public view returns (bytes32) {
    return keccak256(abi.encode("\x19\x01", block.chainid, callId, clubId, applyer, amount, timestamp, validFor));
  }

  // this reduces the cost of encoding a bytes array
  function _hashBytes(bytes memory signature) internal pure returns (bytes32 hash) {
    // solhint-disable-next-line no-inline-assembly
    assembly {
      let data := add(signature, 32)
      let length := mload(signature)
      hash := keccak256(data, length)
    }
  }

  // for future upgrades
  uint256[50] private __gap;
}
