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

contract MomentFactory is Initializable, ValidatableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
  using SafeERC20Upgradeable for LFGToken;

  error NotAuthorized();
  error InvalidInitParameters();
  error ZeroAmount();
  error ZeroAddress();
  error Forbidden();
  error CreationFeeInvalid(); 
  error MomentClubIsLocked(); 
  error MomentClubNotFound();
  error MomentConfInvalid();
  error MomentClubTooMany();  
  error MomentClubVerInvalid(uint256 expectedVer, uint256 actualVer);
  error MomentTokenNotCreated();
  error InvalidAmount(); 
  error InsufficientFunds(); 
  error UnableToSendFunds();
  error Invalid404Address();
  error InsufficientFees();
  error UnableToTransferFunds();
  error SignatureExpired();
  error SignatureAlreadyUsed();
  
  event OperatorUpdated(address operator);
  event TokenFactoryUpdated(address tokenFactory);
  event ProtocolFeePercentUpdate(uint256 feePercent); 
  event SubjectFeePercentUpdate(uint256 feePercent);
  event TGEFeePercentUpdate(uint256 feePercent); 
  event MomentClubCreated(uint256 callId, uint256 clubId, address creator, uint256 creationFee);

  event MomentTokenGeneration(uint256 clubId, address creator, address tokenAddress, address mirrorERC721, address swapPool);

  event MomentClubTrade(
    uint256 callId,
    uint256 clubId,
    uint256 holdingAmount,
    uint256 priceAfterFee,
    uint256 protocolFee,
    uint256 subjectFee,
    uint64  ver
  );

  event MomentTokenMint(uint256 callId, uint256 clubId, address minter, address memeAddress, uint256 amount);

  event MomentNFTTransfer(uint256 clubId, address memeAddress, address mirrorAddress, address from, address to, uint256 tokenId);

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

  struct MomentConfig {
    uint256 liquidityAmount;
    bool isFT; // 404 or ERC20
    string name;
    string symbol;
    string baseURI;
    uint256 baseUnit;
    PriceFormulaType priceType;
    uint256 priceArg1;
    uint256 priceArg2;
  }

  struct MomentClub {
    uint256 clubId;
    bool isLocked;
    address creatorAddress;
    address memeAddress;
    address mirrorERC721;
    address swapPool;
    uint256 lpTokenId;
    uint256 supply;
    uint256 funds;
    uint64 ver;
    MomentConfig momentConf;
  }

  mapping(bytes32 => bool) private _usedSignatures;

  uint256 public baseClubId;

  mapping(uint256 => MomentClub) public momentClubs;
  mapping(uint256 => mapping(address => uint256)) public balanceOf;

  // solhint-disable-next-line var-name-mixedcase
  mapping(address => uint256) private _404Tokens;

  uint256 public protocolFeePercent; 
  uint256 public subjectFeePercent;
  uint256 public tgeFeePercent;

  uint256 public protocolFees;
  uint256 public tgeFees;

  uint256 public creationFees;

  TokenFactory public tokenFactory;
  address public operator;

  IUniswapV3Factory public uniswapV3Factory;
  INonfungiblePositionManager public uniswapPositionManager;
  IWETH public weth;

  uint24 private constant _UNISWAP_POOL_FEE = 10000;
  int24 private _tickLower;
  int24 private _tickUpper;

  modifier onlyOperator() {
    if (_msgSender() != operator) revert NotAuthorized();
    _;
  }

  function initialize( 
    address[] memory validators_, 
    address operator_,
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

    setOperator(operator_);
    setProtocolFeePercent(1 ether / 100); 
    setSubjectFeePercent(1 ether / 100);
    setTGEFeePercent(5 ether / 100); 

    uniswapV3Factory = IUniswapV3Factory(uniswapV3Factory_);
    uniswapPositionManager = INonfungiblePositionManager(uniswapPositionManager_);

    int24 tickSpacing = uniswapV3Factory.feeAmountTickSpacing(_UNISWAP_POOL_FEE);
    _tickLower = (-887272 / tickSpacing) * tickSpacing; // TickMath.MIN_TICK
    _tickUpper = (887272 / tickSpacing) * tickSpacing; // TickMath.MAX_TICK

    weth = IWETH(weth_);
  }

  function setOperator(address operator_) public onlyOwner {
    if (operator_ == address(0)) revert ZeroAddress();
    operator = operator_;
    emit OperatorUpdated(operator);
  }

  function setTokenFactory(address factory) public onlyOwner {
    if (factory == address(0)) revert ZeroAddress();
    tokenFactory = TokenFactory(factory);
    emit TokenFactoryUpdated(factory);
  }
 
  function setProtocolFeePercent(uint256 feePercent_) public virtual onlyOwner {
    protocolFeePercent = feePercent_;
    emit ProtocolFeePercentUpdate(protocolFeePercent);
  }

  function setSubjectFeePercent(uint256 feePercent_) public virtual onlyOwner {
    subjectFeePercent = feePercent_;
    emit SubjectFeePercentUpdate(subjectFeePercent);
  }

  function setTGEFeePercent(uint256 feePercent_) public virtual onlyOwner {
    tgeFeePercent = feePercent_;
    emit TGEFeePercentUpdate(tgeFeePercent);
  }
   
  function _nextClubId() internal returns (uint256) {
    uint256 max = 100000000;
    ++baseClubId;
    if (baseClubId >= max) revert MomentClubTooMany();
    return block.chainid * max + baseClubId;
  }

  function getSupply(uint256 clubId) public view returns (uint256) {
    return momentClubs[clubId].supply;
  }

  function getBalanceOf(uint256 clubId, address user) public view returns (uint256) {
    return balanceOf[clubId][user];
  }

  function checkMemeConf(MomentConfig calldata momentConf) public pure returns (bool) {
    if (bytes(momentConf.name).length == 0) return false;
    if (bytes(momentConf.symbol).length == 0) return false;
    if (bytes(momentConf.baseURI).length == 0) return false;
    if (momentConf.baseUnit < 1e18) return false;

    if (
      momentConf.priceType != PriceFormulaType.Linear &&
      momentConf.priceType != PriceFormulaType.QuadCurve &&
      momentConf.priceType != PriceFormulaType.Fixed
    ) {
      return false;
    }

    return true;
  }

  function newMomentClub(
    uint256 callId_,
    uint256 initBuyAmount_,
    uint256 creationFee_,
    MomentConfig calldata momentConf_,
    uint256 timestamp,
    uint256 validFor,
    bytes calldata signature
  ) external payable whenNotPaused nonReentrant {
    if (!checkMemeConf(momentConf_)) revert MomentConfInvalid();
    if (msg.value < creationFee_) revert CreationFeeInvalid();

    _validateSignature(
      timestamp, 
      validFor, 
      hashForNewMomentClub(block.chainid, callId_, _msgSender(), creationFee_, momentConf_, timestamp, validFor), 
      signature
    );

    uint256 clubId = _nextClubId();
    momentClubs[clubId] = MomentClub({
      clubId: clubId,
      isLocked: false,
      creatorAddress: _msgSender(),
      memeAddress: address(0),
      mirrorERC721: address(0),
      swapPool: address(0),
      lpTokenId: 0,
      supply: 0,
      funds: 0,
      ver: 0,
      momentConf: momentConf_
    });

    creationFees += creationFee_;

    // Club create event must be emit before trade event
    emit MomentClubCreated(callId_, clubId, _msgSender(), creationFee_);

    if (initBuyAmount_ > 0) {
      _buyCardImpl(callId_, clubId, initBuyAmount_, type(uint256).max, msg.value - creationFee_);
    }
  }

  function wantTge(uint256 clubId, uint256 clubVer) external onlyOperator {
    MomentClub storage club = momentClubs[clubId];
    if (club.clubId == clubId) revert MomentClubNotFound();
    if (club.isLocked) revert MomentClubIsLocked();
    if (club.ver != clubVer) revert MomentClubVerInvalid(clubVer, club.ver);
    
    club.isLocked = true;
    _tokenGeneration(club);  
  }

  function _tokenGeneration(MomentClub storage club) internal {
    if (club.momentConf.isFT) {
      club.memeAddress = tokenFactory.newMemeFT(club.momentConf.name, club.momentConf.symbol);
    } else {
      club.memeAddress = tokenFactory.newMeme404(
        club.momentConf.name,
        club.momentConf.symbol,
        club.momentConf.baseURI,
        club.momentConf.baseUnit
      );
      Meme404 meme = Meme404(payable(club.memeAddress));
      club.mirrorERC721 = meme.mirrorERC721();
      _404Tokens[club.memeAddress] = club.clubId;

      string memory addr = Strings.toHexString(club.mirrorERC721); // must all lowercase 0x a-z
      string memory baseURI = string.concat(club.momentConf.baseURI, addr, "/");
      meme.setBaseURI(baseURI);
    }

    _createLP(club);

    emit MomentTokenGeneration(club.clubId, _msgSender(), club.memeAddress, club.mirrorERC721, club.swapPool);
  }

  function _createLP(MomentClub storage club) internal {
    uint256 tgeFee = club.funds * tgeFeePercent / 1 ether;
    address token0 = club.memeAddress;
    address token1 = address(weth);
    uint256 token0Amount = club.momentConf.liquidityAmount;
    uint256 token1Amount = club.funds - tgeFee;
    uint256 nativeAmount = token1Amount;
    bool reverseOrder = false;
 
    if (!(token0 < token1)) {
       token0 = token1;
       token1 = club.memeAddress;
       token0Amount = token1Amount;
       token1Amount = club.momentConf.liquidityAmount;
       reverseOrder = true;
    }
 
    club.swapPool = uniswapV3Factory.createPool(token0, token1, _UNISWAP_POOL_FEE);

    uint160 sqrtPriceX96 = uint160(Math.sqrt(FullMath.mulDiv(token1Amount, 2 ** 192, token0Amount)));
    IUniswapV3Pool(club.swapPool).initialize(sqrtPriceX96);

    if (club.momentConf.isFT) {
      MemeFT meme = MemeFT(payable(club.memeAddress));
      meme.mint(address(this), club.momentConf.liquidityAmount);
      meme.approve(address(uniswapPositionManager), club.momentConf.liquidityAmount);
    } else {
      Meme404 meme = Meme404(payable(club.memeAddress));
      meme.setSkipNFT(true);
      meme.mint(address(this), club.momentConf.liquidityAmount);
      meme.approve(address(uniswapPositionManager), club.momentConf.liquidityAmount);
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

    tgeFees +=  tgeFee; 
    club.lpTokenId = lpTokenId;

    // emit TGEFees(club.clubId, club.memeConf.isNative, tgeNativeFees, tgeLFGFees, tgeFee);
    emit LPCreate(club.clubId, token0, token1, amount0, amount1, lpTokenId, liquidity, reverseOrder);
  }

  function mintMomentToken(
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
    
    MomentClub storage club = momentClubs[clubId];
    if (club.memeAddress == address(0)) revert MomentTokenNotCreated();

    _validateSignature(
      timestamp,
      validFor,
      hashForMintMomentToken(block.chainid, callId, _msgSender(), clubId, amount, timestamp, validFor),
      signature
    );

    // Mint event must happen before nft transfer
    emit MomentTokenMint(callId, clubId, _msgSender(), club.memeAddress, amount);

    if (club.momentConf.isFT) {
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

  function getClubVer(uint256 clubId) public view returns (uint256) {
    return momentClubs[clubId].ver;
  }

  function getPriceByClubId(uint256 clubId, uint256 amount, bool sellingPrice) public view returns (uint256) {
    return
      getPrice(
        momentClubs[clubId].supply - (sellingPrice ? amount : 0),
        amount,
        momentClubs[clubId].momentConf.priceType,
        momentClubs[clubId].momentConf.priceArg1,
        momentClubs[clubId].momentConf.priceArg2
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

  function _buyCardImpl(uint256 callId, uint256 clubId, uint256 amount, uint256 expectedPrice, uint256 remainingPrice) internal {
    if (amount == 0) revert InvalidAmount();
    MomentClub storage club = momentClubs[clubId];
    if (club.isLocked) revert MomentClubIsLocked();
    uint256 actualPrice = getBuyPrice(clubId, amount);
    uint256 protocolFee = getProtocolFee(actualPrice);
    uint256 subjectFee = getSubjectFee(actualPrice);
    uint256 priceAfterFee = actualPrice + protocolFee + subjectFee;
    
    if (priceAfterFee > expectedPrice || priceAfterFee > remainingPrice) { 
      revert InsufficientFunds();
    }
    
    uint256 holdingAmount = balanceOf[clubId][_msgSender()];
    balanceOf[clubId][_msgSender()] = holdingAmount + amount;

    club.funds += actualPrice;
    club.supply += amount;
    club.ver++;

    protocolFees += protocolFee;

    _sendFunds(club.creatorAddress, subjectFee);
    _sendFunds(_msgSender(), remainingPrice - priceAfterFee);

    emit MomentClubTrade(
      callId,
      clubId, 
      holdingAmount + amount,
      priceAfterFee,
      protocolFee,
      subjectFee,
      club.ver
    ); 
  }

  function buyCard(
    uint256 callId, 
    uint256 clubId, 
    uint256 amount, 
    uint256 expectedPrice, 
    uint256 timestamp,
    uint256 validFor,
    bytes calldata signature
  ) external payable whenNotPaused nonReentrant {
    _validateSignature(
      timestamp, 
      validFor, 
      hashForBuyCard(block.chainid, _msgSender(), callId, clubId, amount, expectedPrice, timestamp, validFor), 
      signature
    );

    return _buyCardImpl(callId, clubId, amount, expectedPrice, msg.value);
  }

  function sellCard(
    uint256 callId, 
    uint256 clubId, 
    uint256 amount, 
    uint256 timestamp,
    uint256 validFor,
    bytes calldata signature
  ) external whenNotPaused nonReentrant {
    _validateSignature(
      timestamp, 
      validFor, 
      hashForSellCard(block.chainid, _msgSender(), callId, clubId, amount, timestamp, validFor), 
      signature
    );

    MomentClub storage club = momentClubs[clubId];
    if (club.isLocked) revert MomentClubIsLocked();

    uint256 holdingAmount = balanceOf[clubId][_msgSender()];
    if (amount == 0 || amount > holdingAmount) revert InvalidAmount();

    uint256 actualPrice = getSellPrice(clubId, amount);
    uint256 protocolFee = getProtocolFee(actualPrice); 
    uint256 subjectFee = getSubjectFee(actualPrice);
    uint256 priceAfterFee = actualPrice - protocolFee - subjectFee;

    club.funds -= actualPrice;
    club.supply -= amount;
    club.ver++;
    balanceOf[clubId][_msgSender()] = holdingAmount - amount;

    protocolFees += protocolFee;

    _sendFunds(_msgSender(), priceAfterFee);
    _sendFunds(club.creatorAddress, subjectFee);
    
    emit MomentClubTrade(
      callId,
      clubId,
      holdingAmount - amount,
      priceAfterFee,
      protocolFee,
      subjectFee,
      club.ver
    ); 
  }

  function _sendFunds(address beneficiary, uint256 amount) internal {
    if (beneficiary != address(0) && amount > 0) {
      (bool success, ) = beneficiary.call{value: amount}("");
      if (!success) revert UnableToSendFunds();
    }
  }

  function onNFTTransfer(address from, address to, uint256 tokenId) external {
    uint256 clubId = _404Tokens[_msgSender()];
    if (clubId == 0) revert Invalid404Address();
    address memeAddress = momentClubs[clubId].memeAddress;
    address mirrorERC721 = momentClubs[clubId].mirrorERC721;
    emit MomentNFTTransfer(clubId, memeAddress, mirrorERC721, from, to, tokenId);
  }

  function withdrawProtocolFees(address beneficiary, uint256 amount) external virtual onlyOwner nonReentrant {
    if (beneficiary == address(0)) revert ZeroAddress();
    if (amount == 0) {
      amount = protocolFees;
    }
    if (amount > protocolFees) revert InsufficientFees();
    if (amount > address(this).balance) revert InsufficientFunds();
    protocolFees -= amount;
    (bool success, ) = beneficiary.call{value: amount}("");
    if (!success) revert UnableToTransferFunds();
  }

  function withdrawTGEFees(address beneficiary, uint256 amount) external virtual onlyOwner nonReentrant {
    if (beneficiary == address(0)) revert ZeroAddress();
    if (amount == 0) {
      amount = tgeFees;
    }
    if (amount > tgeFees) revert InsufficientFees();
    if (amount > address(this).balance) revert InsufficientFunds();
    tgeFees -= amount;
    (bool success, ) = beneficiary.call{value: amount}("");
    if (!success) revert UnableToTransferFunds();
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
    MomentClub storage club = momentClubs[clubId];
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
    uint256 validFor,  
    bytes32 hash,
    bytes calldata signature
  ) internal {
    if (timestamp < block.timestamp - validFor) revert SignatureExpired();
    if (!signedByValidator(hash, signature)) revert InvalidSignature();
    _saveSignatureAsUsed(signature);
  }

  function hashForNewMomentClub(
    uint256 chainId,
    uint256 callId,
    address applyer,
    uint256 creationFee,
    MomentConfig calldata momentConf,
    uint256 timestamp,
    uint256 validFor
  ) public pure returns (bytes32) {
    bytes memory part = abi.encodePacked(
      "\x19\x01",
      chainId,
      callId,
      applyer,
      creationFee,
      momentConf.liquidityAmount,
      momentConf.isFT,
      // momentConf.name,
      // momentConf.symbol,
      // momentConf.baseURI,
      momentConf.baseUnit,
      uint256(momentConf.priceType),
      momentConf.priceArg1,
      momentConf.priceArg2,
      timestamp,
      validFor
    );
    return keccak256(part);
  }

  function hashForMintMomentToken(
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

  function hashForBuyCard(
    uint256 chainId, 
    address applyer, 
    uint256 callId, 
    uint256 clubId, 
    uint256 amount, 
    uint256 expectedPrice, 
    uint256 timestamp, 
    uint256 validFor
  ) public pure returns (bytes32) {
    return keccak256(abi.encodePacked("\x19\x01", chainId, applyer, callId, clubId, amount, expectedPrice, timestamp, validFor));
  }

  function hashForSellCard(
    uint256 chainId, 
    address applyer,
    uint256 callId, 
    uint256 clubId, 
    uint256 amount, 
    uint256 timestamp, 
    uint256 validFor
  ) public pure returns (bytes32) {
    return keccak256(abi.encodePacked("\x19\x01", chainId, applyer, callId, clubId, amount, timestamp, validFor));
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
