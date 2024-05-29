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
import {FullMath} from "./FullMath.sol";

contract MemeFactory is Initializable, ValidatableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
  using SafeERC20Upgradeable for LFGToken;

  error InvalidInitParameters();
  error ZeroAmount();
  error ZeroAddress();
  error Forbidden();
  error CreationFeeInvalid();
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
  event ProtocolFeePercentUpdate(uint256 feePercent); 
  event TGEFeePercentUpdate(uint256 feePercent); 
  event MemeClubCreated(uint256 callId, uint256 clubId, address creator, uint256 creationFee);

  event MemeTokenGeneration(uint256 clubId, address creator, address tokenAddress, address mirrorERC721, address swapPool);

  event MemeClubTrade(
    uint256 clubId,
    address trader,
    uint256 supply,
    bool isLocked,
    bool isBuy,
    uint256 tradeAmount,
    uint256 holdingAmount,
    uint256 priceAfterFee,
    uint256 protocolFee
  );

  event MemeTokenMint(uint256 callId, uint256 clubId, address minter, uint256 amount);

  event MemeNFTTransfer(uint256 clubId, address memeAddress, address mirrorAddress, address from, address to, uint256 tokenId);

  event TGEFees(
    uint256 clubId,
    bool isNative,
    uint256 nativeFees,
    uint256 lfgFees, 
    uint256 fee
  );

  event LPCreate(
    uint256 clubId,
    address token0,
    address token1,
    uint256 amount0,
    uint256 amount1,
    uint256 lpTokenId,
    uint256 liquidity,
    bool    reverseOrder
  );

  event WithdrawLiquidityFees(uint256 clubId, address memeToken, address beneficiary, uint256 amount0, uint256 amount1);

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
    address creatorAddress;
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

  // solhint-disable-next-line var-name-mixedcase
  mapping(address => uint256) private _404Tokens;

  uint256 public protocolFeePercent; 
  uint256 public protocolLFGFees;
  uint256 public protocolNativeFees;
  
  uint256 public tgeFeePercent;
  uint256 public tgeLFGFees;
  uint256 public tgeNativeFees;

  uint256 public creationFees;

  TokenFactory public tokenFactory;

  IUniswapV3Factory public uniswapV3Factory;
  INonfungiblePositionManager public uniswapPositionManager;
  IWETH public weth;

  uint24 private constant _UNISWAP_POOL_FEE = 10000;
  int24 private _tickLower;
  int24 private _tickUpper;

  function initialize( 
    address[] memory validators_, 
    address uniswapV3Factory_,
    address uniswapPositionManager_,
    address weth_
  ) public initializer {
    if ((uniswapV3Factory_ == address(0)) || (uniswapPositionManager_ == address(0)) || (weth_ == address(0)))
      revert InvalidInitParameters();

    __Validatable_init();
    __Pausable_init();

    for (uint256 i = 0; i < validators_.length;) {
      updateValidator(validators_[i], true);
      unchecked {
        i++;
      }
    }
 
    setProtocolFeePercent(2 ether / 100); 
    setTGEFeePercent(3 ether / 100); 

    uniswapV3Factory = IUniswapV3Factory(uniswapV3Factory_);
    uniswapPositionManager = INonfungiblePositionManager(uniswapPositionManager_);

    int24 tickSpacing = uniswapV3Factory.feeAmountTickSpacing(_UNISWAP_POOL_FEE);
    _tickLower = (-887272 / tickSpacing) * tickSpacing; // TickMath.MIN_TICK
    _tickUpper = (887272 / tickSpacing) * tickSpacing; // TickMath.MAX_TICK

    weth = IWETH(weth_);
  }

  function setTokenFactory(address factory) public onlyOwner {
    if (factory == address(0)) revert ZeroAddress();
    tokenFactory = TokenFactory(factory);
    emit TokenFactoryUpdated(factory);
  }

  function setLFGToken(address lfgToken_) public onlyOwner {
    if (lfgToken_ == address(0)) revert ZeroAddress();
    lfgToken = LFGToken(lfgToken_);
    lfgToken.approve(address(uniswapPositionManager), type(uint256).max);
    emit LfgTokenUpdate(lfgToken_);
  }
  
  function setProtocolFeePercent(uint256 feePercent_) public virtual onlyOwner {
    protocolFeePercent = feePercent_;
    emit ProtocolFeePercentUpdate(protocolFeePercent);
  }

  function setTGEFeePercent(uint256 feePercent_) public virtual onlyOwner {
    tgeFeePercent = feePercent_;
    emit TGEFeePercentUpdate(tgeFeePercent);
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
    uint256 creationFee_,
    MemeConfig calldata memeConf_,
    uint256 timestamp,
    uint256 validFor,
    bytes calldata signature
  ) external payable whenNotPaused nonReentrant {
    if (!checkMemeConf(memeConf_)) revert MemeConfInvalid();
    if (!memeConf_.isNative && address(lfgToken) == address(0)) revert MemeClubLFGUnsupported();
    if (msg.value < creationFee_) revert CreationFeeInvalid();
    if (initBuyAmount_ >= memeConf_.maxSupply) revert InitBuyTooMany();

    _validateSignature(
      timestamp, 
      validFor, 
      hashForNewMemeClub(block.chainid, callId_, _msgSender(), creationFee_, memeConf_, timestamp, validFor), 
      signature
    );

    uint256 clubId = _nextClubId();
    memeClubs[clubId] = MemeClub({
      clubId: clubId,
      isLocked: false,
      creatorAddress: _msgSender(),
      memeAddress: address(0),
      mirrorERC721: address(0),
      swapPool: address(0),
      lpTokenId: 0,
      supply: 0,
      funds: 0,
      memeConf: memeConf_
    });

    creationFees += creationFee_;

    // Club create event must be emit before trade event
    emit MemeClubCreated(callId_, clubId, _msgSender(), creationFee_);

    if (initBuyAmount_ > 0) {
      uint256 remainingPrice = msg.value - creationFee_;
      _buyCardImpl(clubId, initBuyAmount_, remainingPrice, remainingPrice);
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

      string memory addr = Strings.toHexString(club.mirrorERC721); // must all lowercase 0x a-z
      string memory baseURI = string.concat(club.memeConf.baseURI, addr, "/");
      meme.setBaseURI(baseURI);
    }

    _createLP(club);

    emit MemeTokenGeneration(club.clubId, _msgSender(), club.memeAddress, club.mirrorERC721, club.swapPool);
  }

  function _createLP(MemeClub storage club) internal {
    uint256 tgeFee = club.funds * tgeFeePercent / 1 ether;
    address token0 = club.memeAddress;
    address token1 = address(lfgToken);
    uint256 token0Amount = club.memeConf.liquidityAmount;
    uint256 token1Amount = club.funds - tgeFee;
    uint256 nativeAmount = 0;
    bool reverseOrder = false;
 
    if (club.memeConf.isNative) { 
      token1 = address(weth); 
      nativeAmount = token1Amount;
    }

    if (!(token0 < token1)) {
       token0 = token1;
       token1 = club.memeAddress;
       token0Amount = token1Amount;
       token1Amount = club.memeConf.liquidityAmount;
       reverseOrder = true;
    }
 
    club.swapPool = uniswapV3Factory.createPool(token0, token1, _UNISWAP_POOL_FEE);

    uint160 sqrtPriceX96 = uint160(Math.sqrt(FullMath.mulDiv(token1Amount, 2 ** 192, token0Amount)));
    IUniswapV3Pool(club.swapPool).initialize(sqrtPriceX96);

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
        fee: _UNISWAP_POOL_FEE,
        tickLower: _tickLower,
        tickUpper: _tickUpper,
        amount0Desired: token0Amount,
        amount1Desired: token1Amount,
        amount0Min: 0,
        amount1Min: 0,
        recipient: address(this),
        deadline: block.timestamp
      })
    );

    if (club.memeConf.isNative) tgeNativeFees +=  tgeFee;
    else tgeLFGFees += tgeFee;

    club.lpTokenId = lpTokenId;

    // emit TGEFees(club.clubId, club.memeConf.isNative, tgeNativeFees, tgeLFGFees, tgeFee);
    emit LPCreate(club.clubId, token0, token1, amount0, amount1, lpTokenId, liquidity, reverseOrder);
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
    
    uint256 holdingAmount = balanceOf[clubId][_msgSender()];
    if (holdingAmount == 0) revert Forbidden();
    
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
 
  function getBuyPrice(uint256 clubId, uint256 amount) public view returns (uint256) {
    return getPriceByClubId(clubId, amount, false);
  }

  function getBuyPriceAfterFee(uint256 clubId, uint256 amount) public view returns (uint256) {
    uint256 price = getPriceByClubId(clubId, amount, false);
    uint256 protocolFee = getProtocolFee(price);
    return price + protocolFee;
  }

  function getSellPrice(uint256 clubId, uint256 amount) public view returns (uint256) {
    return getPriceByClubId(clubId, amount, true);
  }

  function getSellPriceAfterFee(uint256 clubId, uint256 amount) public view returns (uint256) {
    uint256 price = getPriceByClubId(clubId, amount, true);
    uint256 protocolFee = getProtocolFee(price);
    return price - protocolFee;
  }

  function _buyCardImpl(uint256 clubId, uint256 amount, uint256 expectedPrice, uint256 remainingPrice) internal {
    if (amount == 0) revert InvalidAmount();
    MemeClub storage club = memeClubs[clubId];
    if (club.isLocked) revert MemeClubIsLocked();
    if (club.memeConf.maxSupply < club.supply + amount) revert MemeClubBuyExceed();
    uint256 actualPrice = getBuyPrice(clubId, amount);
    uint256 protocolFee = getProtocolFee(actualPrice);
    uint256 priceAfterFee = actualPrice + protocolFee;
    if (club.memeConf.isNative) {
      if (priceAfterFee > expectedPrice || priceAfterFee > remainingPrice) revert InsufficientFunds();
    } else { // $LFG
      if (remainingPrice != 0) revert InvalidFunds();
      if (priceAfterFee > expectedPrice) revert InsufficientFunds(); 
      if (lfgToken.balanceOf(_msgSender()) < priceAfterFee) revert InsufficientLFG();
    }

    uint256 holdingAmount = balanceOf[clubId][_msgSender()];
    balanceOf[clubId][_msgSender()] = holdingAmount + amount;

    club.funds += actualPrice;
    club.supply += amount;

    if (club.memeConf.isNative) {
      protocolNativeFees += protocolFee;
      _sendNativeFunds(_msgSender(), remainingPrice - priceAfterFee);
    } else { // $LFG
      protocolLFGFees += protocolFee;
      lfgToken.safeTransferFrom(_msgSender(), address(this), priceAfterFee);
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
      protocolFee
    );

    if (club.memeConf.maxSupply <= club.supply) {
      club.isLocked = true;
      _tokenGeneration(club);  
    } 
  }

  function buyCard(uint256 clubId, uint256 amount, uint256 expectedPrice) external payable whenNotPaused nonReentrant {
    return _buyCardImpl(clubId, amount, expectedPrice, msg.value);
  }

  function sellCard(uint256 clubId, uint256 amount) external whenNotPaused nonReentrant {
    if (amount == 0) revert InvalidAmount();
    MemeClub storage club = memeClubs[clubId];
    if (club.isLocked) revert MemeClubIsLocked();

    uint256 holdingAmount = balanceOf[clubId][_msgSender()];
    if (amount > holdingAmount) revert InvalidAmount();

    uint256 actualPrice = getSellPrice(clubId, amount);
    uint256 protocolFee = getProtocolFee(actualPrice); 
    uint256 priceAfterFee = actualPrice - protocolFee;

    club.funds -= actualPrice;
    club.supply -= amount;
    balanceOf[clubId][_msgSender()] = holdingAmount - amount;

    if (club.memeConf.isNative) {
      protocolNativeFees += protocolFee;
      _sendNativeFunds(_msgSender(), priceAfterFee);
    } else { // $LFG
      protocolLFGFees += protocolFee;
      lfgToken.transfer(_msgSender(), priceAfterFee);
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
      protocolFee
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
      if (amount > balance) revert InsufficientFunds();
      protocolLFGFees -= amount;
      lfgToken.safeTransfer(beneficiary, amount);
    }
  }

  function withdrawTGEFees(address beneficiary, bool native, uint256 amount) external virtual onlyOwner nonReentrant {
    if (beneficiary == address(0)) revert ZeroAddress();
    if (native) {
      if (amount == 0) {
        amount = tgeNativeFees;
      }
      if (amount > tgeNativeFees) revert InsufficientFees();
      if (amount > address(this).balance) revert InsufficientFunds();
      tgeNativeFees -= amount;
      (bool success, ) = beneficiary.call{value: amount}("");
      if (!success) revert UnableToTransferFunds();
    } else {
      uint256 balance = lfgToken.balanceOf(address(this));
      if (amount == 0) {
        amount = tgeLFGFees;
      }
      if (amount > tgeLFGFees) revert InsufficientFees(); 
      if (tgeLFGFees > balance) revert InsufficientFunds();
      tgeLFGFees -= amount;
      lfgToken.safeTransfer(beneficiary, amount);
    }
  }

  function withdrawCreationFees(address beneficiary, uint256 amount) external virtual onlyOwner nonReentrant {
    if (beneficiary == address(0)) revert ZeroAddress(); 
    if (amount == 0) amount = creationFees;
    if (amount > creationFees) revert InsufficientFees();
    if (amount > address(this).balance) revert InsufficientFunds();
    creationFees -= amount;
    (bool success, ) = beneficiary.call{value: amount}("");
    if (!success) revert UnableToTransferFunds(); 
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

  // disabling this function
  function renounceOwnership() public virtual override onlyOwner {
    // if the owner renounces, the contract would stay paused forever
    // if (paused()) revert Forbidden();
    // super.renounceOwnership();
    revert Forbidden();
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
    uint256 creationFee,
    MemeConfig calldata memeConf,
    uint256 timestamp,
    uint256 validFor
  ) public pure returns (bytes32) {
    bytes memory part = abi.encodePacked(
      "\x19\x01",
      chainId,
      callId,
      applyer,
      creationFee,
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
      memeConf.priceArg2,
      timestamp,
      validFor
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
