// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol"; 
import {ValidatableUpgradeable} from "../utils/ValidatableUpgradeable.sol";
import {LFGToken} from "../token/LFGToken.sol";
import {Meme404} from "./Meme404.sol";
import {MemeFT} from "./MemeFT.sol";
import {TokenFactory} from "./TokenFactory.sol";
import {IWETH} from "./IWETH.sol";
import {INonfungiblePositionManager} from "./INonfungiblePositionManager.sol";

contract MemeFactory is Initializable, ValidatableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
  using SafeERC20Upgradeable for LFGToken;

  error InvalidInitParameters();
  error ZeroAmount();
  error ZeroAddress();
  error MemeClubNotFound();
  error MemeClubIsLocked(); 
  error MemeClubBuyExceed();
  error MemeConfInvalid();
  error MemeClubTooMany();
  error MemeClubLFGUnsupported();
  error MemeClubUnlocked();
  error MemeTokenNewDuplidate();
  error MemeTokenNotCreated();
  error InitBuyTooMany();
  error InvalidAmount();
  error InvalidFunds();
  error InsufficientFunds();
  error InsufficientLFG();
  error UnableToSendFunds();
  error Invalid404Address();
  error InsufficientFees();
  error UnableToTransferFunds();
  error SignatureExpired();
  error SignatureAlreadyUsed();
  
  event LfgTokenUpdate(address lfgToken_);
  event TokenFactoryUpdated(address tokenFactory);
  event SubjectFeePercentUpdate(uint256 feePercent);
  event ProtocolFeePercentUpdate(uint256 feePercent);
  event ProtocolFeeDestinationUpdate(address feeDestination);
  event MemeClubCreated(uint256 callId, uint256 clubId, address creator);

  event MemeTokenGeneration(
    uint256 clubId, 
    address creator, 
    address tokenAddress, 
    address mirrorERC721,
    address swapPool
  );

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

  event MemeNFTTransfer(
    uint256 clubId,
    address memeAddress,
    address mirrorAddress,
    address from,
    address to,
    uint256 tokenId
  );

  event LPCreate(
    uint256 clubId,
    address token0,
    address token1,
    uint256 amount0,
    uint256 amount1,
    uint256 lpTokenId,
    uint256 liquidity
  );

  event WithdrawLiquidityFees(
    uint256 clubId,
    address memeToken,
    address beneficiary,
    uint256 amount0,
    uint256 amount1
  );

  enum PriceFormulaType {
    Min,
    Linear,
    QuadCurve, // (supply+1)^2 / A
    Fixed
  }

  struct MemeConfig {
    uint256 maxSupply;
    uint256 liquidityAmount;
    bool isNative; // native or $LFG
    bool isFT; // 404 or ERC20
    string name;
    string symbol;
    string baseURI;
    uint256 baseUnit;
    PriceFormulaType priceType;
    uint256 priceArg1;
    uint256 priceArg2;
  }

  struct MemeClub {
    uint256 clubId;
    bool isLocked;
    address subjectAddress;
    address memeAddress;
    address mirrorERC721;
    address swapPool;
    uint256 lpTokenId;
    uint256 supply;
    uint256 funds;
    MemeConfig memeConf;
  }

  mapping(bytes32 => bool) private _usedSignatures;

  uint256 public baseClubId;
  LFGToken public lfgToken;

  mapping(uint256 => MemeClub) public memeClubs;
  mapping(uint256 => mapping(address => uint256)) public balanceOf;
  mapping(address => uint256) private _404Tokens;

  address public protocolFeeDestination;
  uint256 public protocolFeePercent;
  uint256 public subjectFeePercent;
  uint256 public protocolLFGFees;
  uint256 public protocolNativeFees;
  
  TokenFactory public tokenFactory;

  IUniswapV3Factory public uniswapV3Factory;
  INonfungiblePositionManager public uniswapPositionManager;
  IWETH public weth;

  uint24 private constant _uniswapPoolFee = 10000;
  int24 private _tickLower;
  int24 private _tickUpper;

  function initialize(
    address protocolFeeDestination_,
    address[] memory validators_, 
    address uniswapV3Factory_,
    address uniswapPositionManager_,
    address weth_
  ) public initializer {

    if ((uniswapV3Factory_ == address(0))
      || (uniswapPositionManager_ == address(0))
      || (weth_ == address(0))
    ) revert InvalidInitParameters();

    __Validatable_init();
    __Pausable_init();

    for (uint256 i = 0; i < validators_.length; i++) {
      updateValidator(validators_[i], true);
    }

    setSubjectFeePercent(0 ether / 100);
    setProtocolFeePercent(2 ether / 100);
    setProtocolFeeDestination(protocolFeeDestination_); 

    uniswapV3Factory = IUniswapV3Factory(uniswapV3Factory_);
    uniswapPositionManager = INonfungiblePositionManager(uniswapPositionManager_);

    int24 tickSpacing = uniswapV3Factory.feeAmountTickSpacing(_uniswapPoolFee);
    _tickLower = (-887272 / tickSpacing) * tickSpacing; // TickMath.MIN_TICK
    _tickUpper = (887272 / tickSpacing) * tickSpacing; // TickMath.MAX_TICK

    weth = IWETH(weth_);
  }

  function setTokenFactory(address factory) public onlyOwner {
    tokenFactory = TokenFactory(factory);
    emit TokenFactoryUpdated(factory);
  }

  function setLFGToken(address lfgToken_) public onlyOwner {
    lfgToken = LFGToken(lfgToken_);
    lfgToken.approve(address(uniswapPositionManager), type(uint256).max);
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

  function checkMemeConf(MemeConfig calldata memeConf) public pure returns (bool) {
    if (memeConf.maxSupply == 0) return false;

    if (bytes(memeConf.name).length == 0) return false;
    if (bytes(memeConf.symbol).length == 0) return false;
    if (bytes(memeConf.baseURI).length == 0) return false;
    if (memeConf.baseUnit < 1e18) return false;

    if (
      memeConf.priceType != PriceFormulaType.Linear &&
      memeConf.priceType != PriceFormulaType.QuadCurve &&
      memeConf.priceType != PriceFormulaType.Fixed
    ) {
      return false;
    }

    return true;
  }

  function newMemeClub(
    uint256 callId_,
    uint256 initBuyAmount_,
    MemeConfig calldata memeConf_,
    bytes calldata signature
  ) external payable whenNotPaused nonReentrant {
    if (!checkMemeConf(memeConf_)) revert MemeConfInvalid();
    if (!memeConf_.isNative && address(lfgToken) == address(0)) revert MemeClubLFGUnsupported();
    if (initBuyAmount_ >= memeConf_.maxSupply) revert InitBuyTooMany();

    _validateSignature(block.timestamp, 0, hashForNewMemeClub(block.chainid, callId_, _msgSender(), memeConf_), signature);

    uint256 clubId = _nextClubId();
    memeClubs[clubId] = MemeClub({
      clubId: clubId,
      isLocked: false,
      subjectAddress: _msgSender(),
      memeAddress: address(0),
      mirrorERC721: address(0),
      swapPool: address(0),
      lpTokenId: 0,
      supply: 0,
      funds: 0,
      memeConf: memeConf_
    });

    // Club create event must be emit before trade event
    emit MemeClubCreated(callId_, clubId, _msgSender());
    
    if (initBuyAmount_ > 0) {
      _buyCardImpl(clubId, initBuyAmount_, 0, false);
    }
  }

  function _tokenGeneration(MemeClub storage club) internal { 
    if (club.memeConf.isFT) {
      club.memeAddress = tokenFactory.newMemeFT(club.memeConf.name, club.memeConf.symbol);
    } else {
      club.memeAddress = tokenFactory.newMeme404(
        club.memeConf.name,
        club.memeConf.symbol,
        club.memeConf.baseURI,
        club.memeConf.baseUnit
      );
      Meme404 meme = Meme404(payable(club.memeAddress));
      club.mirrorERC721 = meme.mirrorERC721();
      _404Tokens[club.memeAddress] = club.clubId;

      string memory addr = Strings.toHexString(club.mirrorERC721);  // must all lowercase 0x a-z
      string memory baseURI = string.concat(club.memeConf.baseURI, addr, "/");
      meme.setBaseURI(baseURI);
    }
 
    _createLP(club);

    emit MemeTokenGeneration(club.clubId, _msgSender(), club.memeAddress, club.mirrorERC721, club.swapPool);
  }

  function _createLP(MemeClub storage club) internal {
    address token0 = club.memeAddress;
    address token1 = address(lfgToken);
    uint256 token0Amount = club.memeConf.liquidityAmount;
    uint256 token1Amount = club.funds;
    uint256 nativeAmount = 0;
    
    if (club.memeConf.isNative) { 
      token1 = address(weth); 
      nativeAmount = club.funds;
    }

    if (!(token0 < token1)) {
       token0 = token1;
       token1 = club.memeAddress;
       token0Amount = club.funds;
       token1Amount = club.memeConf.liquidityAmount;
    }
 
    club.swapPool = uniswapV3Factory.createPool(token0, token1, _uniswapPoolFee);

    // uint160 sqrtPriceX96 = uint160((Math.sqrt(token1Amount / token0Amount) * 2)**96);
    // IUniswapV3Pool(club.swapPool).initialize(sqrtPriceX96);
    IUniswapV3Pool(club.swapPool).initialize(2 ** 96);

    if (club.memeConf.isFT) {
      MemeFT meme = MemeFT(payable(club.memeAddress));
      meme.mint(address(this), club.memeConf.liquidityAmount);
      meme.approve(address(uniswapPositionManager), club.memeConf.liquidityAmount);
    } else {
      Meme404 meme = Meme404(payable(club.memeAddress));
      meme.setSkipNFT(true);
      meme.mint(address(this), club.memeConf.liquidityAmount);
      meme.approve(address(uniswapPositionManager), club.memeConf.liquidityAmount);
    }
 
    (uint256 lpTokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = uniswapPositionManager.mint{value: nativeAmount}(
      INonfungiblePositionManager.MintParams({
        token0: token0, 
        token1: token1,
        fee: _uniswapPoolFee,
        tickLower: _tickLower,
        tickUpper: _tickUpper,  
        amount0Desired: token0Amount,
        amount1Desired: token1Amount,
        // amount0Min: token0Amount,
        // amount1Min: token1Amount,
        amount0Min: 0,
        amount1Min: 0,
        recipient: address(this),
        deadline: block.timestamp
      })
    );
    club.lpTokenId = lpTokenId;

    emit LPCreate(club.clubId, token0, token1, amount0, amount1, lpTokenId, liquidity);
  }

  function mintMemeToken(
    uint256 callId,
    uint256 clubId,
    uint256 amount,
    uint256 timestamp,
    uint256 validFor,
    bytes calldata signature
  ) external payable whenNotPaused nonReentrant {
    if (amount == 0) revert ZeroAmount();

    MemeClub storage club = memeClubs[clubId];
    if (club.memeAddress == address(0)) revert MemeTokenNotCreated();

    _validateSignature(
      timestamp, 
      validFor, 
      hashForMintMemeToken(block.chainid, callId, _msgSender(), clubId, amount, timestamp, validFor), 
      signature
    );

    // Mint event must happen before nft transfer
    emit MemeTokenMint(callId, clubId, _msgSender(), amount);

    if (club.memeConf.isFT) {
      MemeFT meme = MemeFT(payable(club.memeAddress));
      meme.mint(_msgSender(), amount);
    } else {
      Meme404 meme = Meme404(payable(club.memeAddress));
      meme.mint(_msgSender(), amount);
    }
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
      uint256 sum1 = ((supply * (supply + 1)) / 2) * priceArg1 + supply * priceArg2;
      uint256 sum2 = (((supply + amount) * (supply + amount + 1)) / 2) * priceArg1 + (supply + amount) * priceArg2;
      price = sum2 - sum1;
    } else if (priceType == PriceFormulaType.QuadCurve) {
      uint256 sum1 = ((supply * (supply + 1) * (2 * supply + 1)) / 6) * priceArg1 + ((supply * (supply + 1)) / 2) * priceArg2;
      uint256 sum2 = (((supply + amount) * (supply + amount + 1) * (2 * (supply + amount) + 1)) / 6) *
        priceArg1 +
        (((supply + amount) * (supply + 1 + amount)) / 2) *
        priceArg2;
      price = sum2 - sum1;
    } else if (priceType == PriceFormulaType.Fixed) {
      price = amount * priceArg1;
    }
    return price;
  }

  function getPriceByClubId(uint256 clubId, uint256 amount, bool sellingPrice) public view returns (uint256) {
    return
      getPrice(
        memeClubs[clubId].supply - (sellingPrice ? amount : 0),
        amount,
        memeClubs[clubId].memeConf.priceType,
        memeClubs[clubId].memeConf.priceArg1,
        memeClubs[clubId].memeConf.priceArg2
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

  function getSellPrice(uint256 clubId, uint256 amount) public view returns (uint256) {
    return getPriceByClubId(clubId, amount, true);
  }

  function getSellPriceAfterFee(uint256 clubId, uint256 amount) public view returns (uint256) {
    uint256 price = getPriceByClubId(clubId, amount, true);
    uint256 protocolFee = getProtocolFee(price);
    uint256 subjectFee = getSubjectFee(price);
    return price - protocolFee - subjectFee;
  }

  function _buyCardImpl(uint256 clubId, uint256 amount, uint256 expectedPrice, bool checkPrice) internal {
    if (amount == 0) revert InvalidAmount();
    MemeClub storage club = memeClubs[clubId];
    if (club.isLocked) revert MemeClubIsLocked();
    if (club.memeConf.maxSupply < club.supply + amount) revert MemeClubBuyExceed();
    uint256 actualPrice = getBuyPrice(clubId, amount);
    uint256 protocolFee = getProtocolFee(actualPrice);
    uint256 subjectFee = getSubjectFee(actualPrice);
    uint256 priceAfterFee = actualPrice + protocolFee + subjectFee;
    if (club.memeConf.isNative) {
      if (priceAfterFee > msg.value) revert InsufficientFunds();
    } else { // $LFG
      if (msg.value != 0) revert InvalidFunds();
      if (checkPrice) {
        if (priceAfterFee > expectedPrice) revert InsufficientFunds();
      }
      if (lfgToken.balanceOf(_msgSender()) < priceAfterFee) revert InsufficientLFG();
    }

    uint256 holdingAmount = balanceOf[clubId][_msgSender()];
    balanceOf[clubId][_msgSender()] = holdingAmount + amount;

    club.funds += actualPrice;
    club.supply += amount;
    
    if (club.memeConf.isNative) {
      protocolNativeFees += protocolFee;
      _sendNativeFunds(_msgSender(), msg.value - priceAfterFee);
      _sendNativeFunds(club.subjectAddress, subjectFee);
    } else { // $LFG
      protocolLFGFees += protocolFee;
      lfgToken.safeTransferFrom(_msgSender(), address(this), priceAfterFee);
      if (subjectFee > 0) {
        lfgToken.transfer(club.subjectAddress, subjectFee);
      }
    }

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

    if (club.memeConf.maxSupply <= club.supply) {
      club.isLocked = true;
      _tokenGeneration(club);  
    }
  }

  function buyCard(uint256 clubId, uint256 amount, uint256 expectedPrice) external payable whenNotPaused nonReentrant {
    return _buyCardImpl(clubId, amount, expectedPrice, true);
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

    if (club.memeConf.isNative) {
      protocolNativeFees += protocolFee;
      _sendNativeFunds(_msgSender(), priceAfterFee);
      _sendNativeFunds(club.subjectAddress, subjectFee);
    } else {
      // $LFG
      protocolLFGFees += protocolFee;
      lfgToken.transfer(_msgSender(), priceAfterFee);
      if (subjectFee > 0) {
        lfgToken.transfer(club.subjectAddress, subjectFee);
      }
    }

    emit MemeClubTrade(
      clubId,
      _msgSender(),
      club.supply,
      club.isLocked,
      false,
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

  function onNFTTransfer(address from, address to, uint256 tokenId) external {
    uint256 clubId = _404Tokens[_msgSender()];
    if (clubId == 0) revert Invalid404Address();
    address memeAddress = memeClubs[clubId].memeAddress;
    address mirrorERC721 = memeClubs[clubId].mirrorERC721;
    emit MemeNFTTransfer(clubId, memeAddress, mirrorERC721, from, to, tokenId);
  }

  function withdrawProtocolFees(address beneficiary, bool native, uint256 amount) external virtual onlyOwner nonReentrant {
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

  function withdrawLiquidityFees(uint256 clubId, address beneficiary) external virtual onlyOwner nonReentrant {
    MemeClub storage club = memeClubs[clubId];
    if (club.memeAddress == address(0)) revert ZeroAddress();
    (uint256 amount0, uint256 amount1) = uniswapPositionManager.collect(
      INonfungiblePositionManager.CollectParams({
        tokenId: club.lpTokenId,
        recipient: beneficiary,
        amount0Max: type(uint128).max,
        amount1Max: type(uint128).max
      })
    );
    emit WithdrawLiquidityFees(clubId, club.memeAddress, beneficiary, amount0, amount1);
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
    uint256 chainId, 
    uint256 callId, 
    address applyer, 
    MemeConfig calldata memeConf
  ) public pure returns (bytes32) {
    bytes memory part = abi.encodePacked(
      "\x19\x01", 
      chainId, 
      callId, 
      applyer,
      memeConf.maxSupply,
      memeConf.liquidityAmount,
      memeConf.isNative,
      memeConf.isFT,
      // memeConf.name,
      // memeConf.symbol,
      // memeConf.baseURI,
      memeConf.baseUnit,
      uint256(memeConf.priceType),
      memeConf.priceArg1,
      memeConf.priceArg2
    );
    return keccak256(part); 
  }

  function hashForMintMemeToken(
    uint256 chainId,
    uint256 callId,
    address applyer,
    uint256 clubId,
    uint256 amount,
    uint256 timestamp,
    uint256 validFor
  ) public pure returns (bytes32) {
    return keccak256(abi.encodePacked("\x19\x01", chainId, callId, clubId, applyer, amount, timestamp, validFor));
  }

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
