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
import {IEntropy} from "@pythnetwork/entropy-sdk-solidity/IEntropy.sol";
import {IEntropyConsumer} from "@pythnetwork/entropy-sdk-solidity/IEntropyConsumer.sol";
import {ValidatableUpgradeable} from "../utils/ValidatableUpgradeable.sol";
import {Meme404} from "./Meme404.sol";
import {MemeFT} from "./MemeFT.sol";
import {TokenFactory} from "./TokenFactory.sol";
import {IWETH} from "./IWETH.sol";
import {INonfungiblePositionManager} from "./INonfungiblePositionManager.sol";
import {FullMath} from "./FullMath.sol";

contract MomentFactory is Initializable, ValidatableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable, IEntropyConsumer {
  
  error NotAuthorized();
  error InvalidInitParameters();
  error InvalidParameters();
  error ZeroAmount();
  error ZeroAddress();
  error Forbidden();
  error CreationFeeInvalid(); 
  error MomentClubUnlocked();
  error MomentClubIsLocked(); 
  error MomentClubNotFound();
  error MomentConfInvalid();
  error MomentClubTooMany();  
  error MomentClubVerInvalid(uint256 expectedVer, uint256 actualVer);
  error MomentTokenNotCreated();
  error MomentClubTGEDone();
  error InvalidSequenceNumber(uint64 sequenceNumber);
  error InvalidAmount(); 
  error InsufficientFunds(); 
  error UnableToSendFunds();
  error Invalid404Address();
  error InsufficientFees();
  error UnableToTransferFunds();
  error SignatureExpired();
  error SignatureAlreadyUsed();
  error EntropyFeeUnacceptable(uint256 entroyFeeMax, uint256 entropyFee);
   
  event TokenFactoryUpdated(address tokenFactory);
  event ProtocolFeePercentUpdate(uint256 feePercent); 
  event SubjectFeePercentUpdate(uint256 feePercent);
  event EntropyFeeMaxUpdate(uint256 feeMax);
  event TGEFeePercentUpdate(uint256 feePercent); 
  event MomentClubCreated(uint256 callId, uint256 clubId, address creator, uint256 creationFee);

  event MomentTokenGeneration(uint256 clubId, address creator, address tokenAddress, address mirrorERC721, address swapPool);

  event BuyCardCommit(
      uint64 sequenceNumber,
      bytes32 userRandomNumber,
      uint256 clubId,
      uint256 buyAmount,
      uint256 expectedPrice,
      uint256 remainFunds
  );

  event BuyCardReveal(uint64 sequenceNumber, bytes32 rngNumber, uint256 clubId, string comments);

  event MomentCardUpdate( 
    address owner, 
    uint256 clubId,
    uint256 cardNo, 
    uint256 cardSupply,
    uint256 holdAmount
  );

  event MomentClubTrade(
    uint256 clubId,
    address trader,
    uint256 supply,
    bool isLocked,
    uint256 amount,
    bool isBuy,
    uint256 priceAfterFee,
    uint64 sequenceNumber
  );

  event MomentTokenMint(uint256 clubId, address minter, address memeAddress, uint256 amount);

  event MomentNFTTransfer(uint256 clubId, address memeAddress, address mirrorAddress, address from, address to, uint256 tokenId);
 
  event LPCreate(
    uint256 clubId,
    address token0,
    address token1,
    uint256 amount0,
    uint256 amount1,
    uint256 lpTokenId,
    uint256 liquidity,
    bool reverseOrder
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
    uint256 seriesTotal;
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
    MomentConfig momentConf; 
  }

  struct MomentOrder {  
    uint256 clubId;
    address trader;
    uint256 amount;
    uint256 expectedPrice;
    uint256 remainFunds;
    uint256 commitTime;
  }

  mapping(bytes32 => bool) private _usedSignatures;

  uint256 public baseClubId;

  mapping(uint256 => MomentClub) public momentClubs;
  mapping(uint256 => MomentOrder) public orders;

  // clubId => series supply
  mapping(uint256 => uint256) public seriesSupply;

  // clubId => (cardNo => supply)
  mapping(uint256 => mapping(uint256 => uint256)) public cardSupply;

  // address => (clubId => (cardNo => holdAmount))
  mapping(address => mapping(uint256 => mapping(uint256 => uint256))) public balanceOf;

  // solhint-disable-next-line var-name-mixedcase
  mapping(address => uint256) private _404Tokens;

  uint256 public protocolFeePercent; 
  uint256 public subjectFeePercent;
  uint256 public tgeFeePercent;

  uint256 public protocolFees;
  uint256 public tgeFees;

  uint256 public creationFees;

  TokenFactory public tokenFactory;
  
  IUniswapV3Factory public uniswapV3Factory;
  INonfungiblePositionManager public uniswapPositionManager;
  IWETH public weth;

  uint24 private constant _UNISWAP_POOL_FEE = 10000;
  int24 private _tickLower;
  int24 private _tickUpper;

  IEntropy public entropy;
  address public entropyProvider;
  uint256 public entropyFeeMax; 

  function initialize( 
    address[] calldata validators_,  
    address uniswapV3Factory_,
    address uniswapPositionManager_,
    address weth_,
    address entropy_
  ) public initializer {
    if ((uniswapV3Factory_ == address(0)) 
      || (uniswapPositionManager_ == address(0)) 
      || (weth_ == address(0))
      || (entropy_ == address(0)))
      revert InvalidInitParameters();

    __Validatable_init();
    __Pausable_init();

    for (uint256 i = 0; i < validators_.length;) {
      updateValidator(validators_[i], true);
      unchecked {
        i++;
      }
    }
 
    setProtocolFeePercent(1 ether / 100); 
    setSubjectFeePercent(1 ether / 100);
    setTGEFeePercent(5 ether / 100); 

    uniswapV3Factory = IUniswapV3Factory(uniswapV3Factory_);
    uniswapPositionManager = INonfungiblePositionManager(uniswapPositionManager_);

    int24 tickSpacing = uniswapV3Factory.feeAmountTickSpacing(_UNISWAP_POOL_FEE);
    _tickLower = (-887272 / tickSpacing) * tickSpacing; // TickMath.MIN_TICK
    _tickUpper = (887272 / tickSpacing) * tickSpacing; // TickMath.MAX_TICK

    weth = IWETH(weth_);

    entropy = IEntropy(entropy_);
    entropyProvider = entropy.getDefaultProvider();
    setEntropyFeeMax(1 ether / 10000);
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
   
  function setEntropyFeeMax(uint256 feeMax) public virtual onlyOwner {
    entropyFeeMax = feeMax;
    emit EntropyFeeMaxUpdate(feeMax);
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
  
  function checkMemeConf(MomentConfig calldata momentConf) public pure returns (bool) {
    if (momentConf.liquidityAmount < 1e18) return false;
    if (momentConf.seriesTotal == 0 || momentConf.seriesTotal > 500) return false;
    if (bytes(momentConf.name).length == 0) return false;
    if (bytes(momentConf.symbol).length == 0) return false;
    if (bytes(momentConf.baseURI).length == 0) return false;
    if (momentConf.baseUnit < 1e18) return false;
    
    if (momentConf.priceType != PriceFormulaType.Linear 
      && momentConf.priceType != PriceFormulaType.QuadCurve 
      && momentConf.priceType != PriceFormulaType.Fixed) {
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
      momentConf: momentConf_
    });

    creationFees += creationFee_;

    // Club create event must be emit before trade event
    emit MomentClubCreated(callId_, clubId, _msgSender(), creationFee_);

    if (initBuyAmount_ > 0) {
      _buyCardCommit(clubId, initBuyAmount_, type(uint256).max, msg.value - creationFee_);
    }
  }

  function wantTge(uint256 clubId) public {
    MomentClub storage club = momentClubs[clubId];
    if (club.clubId == clubId) revert MomentClubNotFound();
    if (!club.isLocked) revert MomentClubUnlocked();
    if (club.memeAddress != address(0)) revert MomentClubTGEDone(); 

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

    emit LPCreate(club.clubId, token0, token1, amount0, amount1, lpTokenId, liquidity, reverseOrder);
  }

  function mintMomentToken(uint256 clubId, uint256[] calldata cardArr, uint256[] calldata amountArr) external payable whenNotPaused nonReentrant {
    if (cardArr.length == 0 || cardArr.length != amountArr.length) revert InvalidParameters();
    MomentClub storage club = momentClubs[clubId];
    if (club.isLocked) revert MomentClubIsLocked();
    
    uint256 mintTokenAmount = 0;
    uint256 slotTokenAmount = club.momentConf.liquidityAmount / club.momentConf.seriesTotal;

    for (uint256 i = 0; i < cardArr.length; i++) {
      uint256 cardNo = cardArr[i];
      uint256 cardAmount = amountArr[i];

      uint256 holdAmount = balanceOf[_msgSender()][clubId][cardNo];
      if (cardAmount == 0 || cardAmount > holdAmount) revert InvalidAmount();
      balanceOf[_msgSender()][clubId][cardNo] = holdAmount - cardAmount;
    
      uint256 supply = cardSupply[clubId][cardNo];
      mintTokenAmount = mintTokenAmount + slotTokenAmount * cardAmount / supply;

      emit MomentCardUpdate(_msgSender(), clubId, cardNo, supply - cardAmount, holdAmount - cardAmount);
    }
 
    // Mint event must happen before nft transfer
    emit MomentTokenMint(clubId, _msgSender(), club.memeAddress, mintTokenAmount);

    if (club.momentConf.isFT) {
      MemeFT meme = MemeFT(payable(club.memeAddress));
      meme.mint(_msgSender(), mintTokenAmount);
    } else {
      Meme404 meme = Meme404(payable(club.memeAddress));
      meme.mint(_msgSender(), mintTokenAmount);
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
      uint256 sum2 = (((supply + amount) * (supply + amount + 1) * (2 * (supply + amount) + 1)) / 6) * priceArg1 
        + (((supply + amount) * (supply + 1 + amount)) / 2) * priceArg2;
      price = sum2 - sum1;
    } else if (priceType == PriceFormulaType.Fixed) {
      price = amount * priceArg1;
    }
    return price;
  }
 
  function getPriceByClubId(uint256 clubId, uint256 amount, bool sellingPrice) public view returns (uint256) {
    return getPrice(
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

  function _buyCardCommit(uint256 clubId, uint256 amount, uint256 expectedPrice, uint256 remainFunds) internal {
    if (amount == 0) revert InvalidAmount();
    MomentClub storage club = momentClubs[clubId];
    if (club.isLocked) revert MomentClubIsLocked();
    
    uint256 actualPrice = getBuyPrice(clubId, amount);
    uint256 protocolFee = getProtocolFee(actualPrice);
    uint256 subjectFee = getSubjectFee(actualPrice);
    uint256 priceAfterFee = actualPrice + protocolFee + subjectFee;
    
    uint256 entropyFee = getEntropyFee();
    if (entropyFee > entropyFeeMax) revert EntropyFeeUnacceptable(entropyFeeMax, entropyFee);

    if (priceAfterFee > expectedPrice || (priceAfterFee + entropyFee) > remainFunds) { 
      revert InsufficientFunds();
    }
    
    bytes32 userRandomNumber = keccak256(abi.encodePacked(block.timestamp, blockhash(block.number - 1), _msgSender()));
    uint64 sequenceNumber = entropy.requestWithCallback{value: entropyFee}(entropyProvider, userRandomNumber);

    if (orders[sequenceNumber].clubId != 0) {
      revert InvalidSequenceNumber(sequenceNumber);
    }
    
    orders[sequenceNumber] = MomentOrder({ 
      clubId: clubId,
      trader: _msgSender(),
      amount: amount,
      expectedPrice: expectedPrice,
      remainFunds: remainFunds - entropyFee,
      commitTime: block.timestamp
    });
 
    emit BuyCardCommit(sequenceNumber, userRandomNumber, clubId, amount, expectedPrice, remainFunds); 
  }

  function _checkOrder(MomentOrder memory order, uint64 sequenceNumber, bytes32 rngNumber) internal returns (bool) { 
    if (order.clubId == 0) {
      _sendFunds(order.trader, order.remainFunds);
      emit BuyCardReveal(sequenceNumber, rngNumber, 0, "Not found order");
      return false;
    }
    
    MomentClub storage club = momentClubs[order.clubId];
    if (club.clubId == 0) {
      _sendFunds(order.trader, order.remainFunds);
      emit BuyCardReveal(sequenceNumber, rngNumber, 0, "Not found club");
      return false;
    }

    if (club.isLocked) {
      _sendFunds(order.trader, order.remainFunds);
      emit BuyCardReveal(sequenceNumber, rngNumber, club.clubId, "Locked club");
      return false;
    }

    uint256 actualPrice = getBuyPrice(order.clubId, order.amount);
    uint256 protocolFee = getProtocolFee(actualPrice);
    uint256 subjectFee = getSubjectFee(actualPrice);
    uint256 priceAfterFee = actualPrice + protocolFee + subjectFee;

    if (priceAfterFee > order.expectedPrice || priceAfterFee > order.remainFunds) { 
      _sendFunds(order.trader, order.remainFunds);
      emit BuyCardReveal(sequenceNumber, rngNumber, club.clubId, "Insufficient funds");
      return false;
    }

    emit BuyCardReveal(sequenceNumber, rngNumber, club.clubId, "OK");

    return true;
  }

  function _executeOrder(MomentOrder memory order, bytes32 rngNumber) internal nonReentrant{
    uint256 clubId = order.clubId;
    MomentClub storage club = momentClubs[clubId]; 
    for (uint256 i = 1; i <= order.amount; i++) {
      uint256 rng = uint256(keccak256(abi.encodePacked(rngNumber, order.trader, block.timestamp, i)));
      uint256 cardNo = 1 + uint256(rng % club.momentConf.seriesTotal);
      
      uint256 holdAmount = balanceOf[order.trader][clubId][cardNo];
      balanceOf[order.trader][clubId][cardNo] = holdAmount + 1;
      
      uint256 supply = cardSupply[clubId][cardNo];
      cardSupply[clubId][cardNo] = supply + 1;
      if (supply == 0) {
        seriesSupply[clubId] += 1;
        if (seriesSupply[clubId] >= club.momentConf.seriesTotal) {
          club.isLocked = true;
        }
      }

      emit MomentCardUpdate(order.trader, clubId, cardNo, supply + 1, holdAmount + 1);
    }
  }

  function _buyCardReveal(uint64 sequenceNumber, bytes32 rngNumber) internal nonReentrant {
    MomentOrder memory order = orders[sequenceNumber];
    delete orders[sequenceNumber];
    if (!_checkOrder(order, sequenceNumber, rngNumber)) return;

    MomentClub storage club = momentClubs[order.clubId];

    uint256 actualPrice = getBuyPrice(club.clubId, order.amount);
    uint256 protocolFee = getProtocolFee(actualPrice);
    uint256 subjectFee = getSubjectFee(actualPrice);
    uint256 priceAfterFee = actualPrice + protocolFee + subjectFee;

    club.funds += actualPrice;
    club.supply += order.amount;
  
    protocolFees += protocolFee;

    _sendFunds(club.creatorAddress, subjectFee);
    _sendFunds(_msgSender(), order.remainFunds - priceAfterFee);

    _executeOrder(order, rngNumber);

    emit MomentClubTrade(club.clubId, order.trader, club.supply, club.isLocked, order.amount, true, priceAfterFee, sequenceNumber);
  }
  
  function buyCard(uint256 clubId, uint256 amount, uint256 expectedPrice) external payable whenNotPaused nonReentrant { 
    _buyCardCommit(clubId, amount, expectedPrice, msg.value);
  }

  function sellCard(uint256 clubId, uint256[] calldata cardArr, uint256[] calldata amountArr) external whenNotPaused nonReentrant {
    if (cardArr.length == 0 || cardArr.length != amountArr.length) revert InvalidParameters();
    
    MomentClub storage club = momentClubs[clubId];
    if (club.isLocked) revert MomentClubIsLocked();

    uint256 sellAmount = 0;
    for (uint256 i = 0; i < cardArr.length; i++) {
      uint256 cardNo = cardArr[i];
      uint256 cardAmount = amountArr[i];

      uint256 holdAmount = balanceOf[_msgSender()][clubId][cardNo];
      if (cardAmount == 0 || cardAmount > holdAmount) revert InvalidAmount();
      balanceOf[_msgSender()][clubId][cardNo] = holdAmount - cardAmount;
      uint256 supply = cardSupply[clubId][cardNo];
      cardSupply[clubId][cardNo] = supply - cardAmount;
      if (supply == cardAmount) {
        seriesSupply[clubId] -= 1;
      }

      sellAmount += cardAmount;

      emit MomentCardUpdate(_msgSender(), clubId, cardNo, supply - cardAmount, holdAmount - cardAmount);
    }

    uint256 actualPrice = getSellPrice(clubId, sellAmount);
    uint256 protocolFee = getProtocolFee(actualPrice); 
    uint256 subjectFee = getSubjectFee(actualPrice);
    uint256 priceAfterFee = actualPrice - protocolFee - subjectFee;

    club.funds -= actualPrice;
    club.supply -= sellAmount;

    protocolFees += protocolFee;

    _sendFunds(_msgSender(), priceAfterFee);
    _sendFunds(club.creatorAddress, subjectFee);
 
    emit MomentClubTrade(
      clubId,
      _msgSender(),
      club.supply,
      club.isLocked,
      sellAmount,
      false,
      priceAfterFee,
      0
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

  function getEntropyFee() public view returns (uint256)  {
    return entropy.getFee(entropyProvider);
  }

  function getEntropy() internal view override returns (address) {
    return address(entropy);
  }

  function entropyCallback(uint64 sequenceNumber, address /*provider*/, bytes32 randomNumber) internal override {
    _buyCardReveal(sequenceNumber, randomNumber);
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
    return keccak256(abi.encodePacked(
      "\x19\x01",
      chainId,
      callId,
      applyer,
      creationFee,
      momentConf.liquidityAmount,
      momentConf.seriesTotal,
      momentConf.isFT,
      momentConf.baseUnit,
      uint256(momentConf.priceType),
      momentConf.priceArg1,
      momentConf.priceArg2,
      timestamp,
      validFor
    ));
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
