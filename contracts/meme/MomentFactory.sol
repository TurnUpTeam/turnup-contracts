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
import {MemeFT} from "../meme/MemeFT.sol";
import {MomentNFT} from "../meme/MomentNFT.sol";
import {MomentToken} from "../meme/MomentToken.sol";
import {IWETH} from "../meme/IWETH.sol";
import {INonfungiblePositionManager} from "../meme/INonfungiblePositionManager.sol";
import {FullMath} from "../meme/FullMath.sol";

contract MomentFactory is Initializable, ValidatableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
  
  error NotAuthorized();
  error InvalidInitParameters();
  error InvalidParameters(); 
  error ZeroAddress();
  error Forbidden();
  error CreationFeeInvalid(); 
  error MomentClubUnlocked();
  error MomentClubIsLocked(); 
  error MomentClubNotFound();
  error MomentConfInvalid();
  error MomentClubTooMany();  
  error MomentClubVerInvalid(uint256 expectedVer, uint256 actualVer);
  error MomentClubTGEDone();
  error MomentTokenNotCreated();
  error InvalidAmount(); 
  error InsufficientFunds(); 
  error UnableToSendFunds(); 
  error InvalidNFTSender();
  error InsufficientFees();
  error UnableToTransferFunds();
  error SignatureExpired();
  error SignatureAlreadyUsed(); 
   
  event MomentTokenUpdated(address momentToken);
  event ProtocolFeePercentUpdate(uint256 feePercent); 
  event SubjectFeePercentUpdate(uint256 feePercent);
  event TGEFeePercentUpdate(uint256 feePercent); 
  event MomentClubCreated(uint256 callId, uint256 clubId, address creator, uint256 creationFee);

  event MomentTokenGeneration(uint256 clubId, address creator, address tokenAddress, address nftAddress, address swapPool);
 
  event MomentCardUpdate( 
    address owner, 
    uint256 clubId,
    uint256 cardNo, 
    uint256 cardSupply,
    uint256 holdAmount,
    uint256 updateAmount
  );

  event MomentClubTrade(
    uint256 clubId, 
    address trader,
    uint256 supply,
    bool isLocked,
    uint256 amount,
    bool isBuy,
    uint256 priceAfterFee
  );

  event MomentNFTMint(uint256 clubId, address  minter, address nftAddress, uint256 cardNo, uint256 tokenId);

  event MomentTokenMint(uint256 clubId, address minter, address memeAddress, uint256 amount);

  event MomentNFTTransfer(uint256 clubId, address memeAddress, address nftAddress, address from, address to, uint256 tokenId);
 
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
    uint256 mintTotal;
    uint256 seriesTotal;  
    string name;
    string symbol;
    string baseURI; 
    PriceFormulaType priceType;
    uint256 priceArg1;
    uint256 priceArg2;
  }

  struct MomentClub {
    uint256 clubId;
    bool isLocked;
    address creatorAddress;
    address memeAddress;
    address nftAddress; 
    address swapPool;
    uint256 lpTokenId;
    uint256 supply;
    uint256 funds; 
    MomentConfig momentConf; 
  }

  uint256 public baseClubId;

  mapping(bytes32 => bool) private _usedSignatures;

  mapping(uint256 => MomentClub) public momentClubs;
  
  // clubId => series supply
  mapping(uint256 => uint256) public seriesSupply;

  // clubId => (cardNo => supply)
  mapping(uint256 => mapping(uint256 => uint256)) public cardSupply;

  // address => (clubId => (cardNo => holdAmount))
  mapping(address => mapping(uint256 => mapping(uint256 => uint256))) public balanceOf;

  uint256 private _rngNumber;
  
  uint256 public protocolFeePercent; 
  uint256 public subjectFeePercent;
  uint256 public tgeFeePercent;

  uint256 public protocolFees;
  uint256 public tgeFees;

  uint256 public creationFees;

  MomentToken public momentToken;
  
  IUniswapV3Factory public uniswapV3Factory;
  INonfungiblePositionManager public uniswapPositionManager;
  IWETH public weth;

  uint24 private constant _UNISWAP_POOL_FEE = 10000;
  int24 private _tickLower;
  int24 private _tickUpper;

  uint256[] private _orderItems; 
  mapping(uint256 => uint256) private _orderCards;

  function initialize( 
    address[] calldata validators_,  
    address uniswapV3Factory_,
    address uniswapPositionManager_,
    address weth_
  ) public initializer {
    if ((uniswapV3Factory_ == address(0)) 
      || (uniswapPositionManager_ == address(0)) 
      || (weth_ == address(0)))
      revert InvalidInitParameters();

    __Validatable_init();
    __Pausable_init();

    for (uint256 i = 0; i < validators_.length; i++) {
      updateValidator(validators_[i], true);
    }
 
    setProtocolFeePercent(5 ether / 100); 
    setSubjectFeePercent(5 ether / 100);
    setTGEFeePercent(5 ether / 100); 

    uniswapV3Factory = IUniswapV3Factory(uniswapV3Factory_);
    uniswapPositionManager = INonfungiblePositionManager(uniswapPositionManager_);

    int24 tickSpacing = uniswapV3Factory.feeAmountTickSpacing(_UNISWAP_POOL_FEE);
    _tickLower = (-887272 / tickSpacing) * tickSpacing; // TickMath.MIN_TICK
    _tickUpper = (887272 / tickSpacing) * tickSpacing; // TickMath.MAX_TICK

    weth = IWETH(weth_);
  }
 
  function setMomentToken(address addr) public onlyOwner {
    if (addr == address(0)) revert ZeroAddress();
    momentToken = MomentToken(addr);
    emit MomentTokenUpdated(addr);
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
  
  function checkMemeConf(MomentConfig calldata momentConf) public pure returns (bool) {
    if (momentConf.liquidityAmount < 1e18) return false;
    if (momentConf.seriesTotal == 0 || momentConf.seriesTotal > 500) return false;
    if (bytes(momentConf.name).length == 0) return false;
    if (bytes(momentConf.symbol).length == 0) return false;
    if (bytes(momentConf.baseURI).length == 0) return false;
    
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
      nftAddress: address(0),
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
      _buyCardImpl(clubId, initBuyAmount_, type(uint256).max, msg.value - creationFee_);
    }
  }

  function wantTge(MomentClub storage club) internal { 
    if (!club.isLocked) revert MomentClubUnlocked();
    if (club.memeAddress != address(0)) revert MomentClubTGEDone(); 

    club.memeAddress = momentToken.newMomentFT(club.momentConf.name, club.momentConf.symbol);
    club.nftAddress = momentToken.newMomentNFT(club.clubId, club.momentConf.name, club.momentConf.symbol, club.momentConf.baseURI);
    
    string memory addr = Strings.toHexString(club.nftAddress); // must all lowercase 0x a-z
    string memory baseURI = string.concat(club.momentConf.baseURI, addr, "/");
    MomentNFT nft = MomentNFT(club.nftAddress);
    nft.setBaseURI(baseURI);

    _createLP(club);

    emit MomentTokenGeneration(club.clubId, _msgSender(), club.memeAddress, club.nftAddress, club.swapPool);
  }

  function _createLP(MomentClub storage club) internal {
    uint256 tgeFee = club.funds * tgeFeePercent / 1 ether;
    address token0 = club.memeAddress;
    address token1 = address(weth);
    uint256 token0Amount = club.momentConf.liquidityAmount;
    uint256 token1Amount = club.funds - tgeFee;
    bool reverseOrder = false;
 
    if (token0 >= token1) {
       token0 = token1;
       token1 = club.memeAddress;
       token0Amount = token1Amount;
       token1Amount = club.momentConf.liquidityAmount;
       reverseOrder = true;
    }
 
    club.swapPool = uniswapV3Factory.createPool(token0, token1, _UNISWAP_POOL_FEE);

    uint160 sqrtPriceX96 = uint160(Math.sqrt(FullMath.mulDiv(token1Amount, 2 ** 192, token0Amount)));
    IUniswapV3Pool(club.swapPool).initialize(sqrtPriceX96);

    MemeFT meme = MemeFT(payable(club.memeAddress));
    meme.mint(address(this), club.momentConf.liquidityAmount);
    meme.approve(address(uniswapPositionManager), club.momentConf.liquidityAmount);
     
    (uint256 lpTokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = uniswapPositionManager.mint{value: club.funds - tgeFee}(
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
    if (club.memeAddress == address(0)) revert MomentTokenNotCreated();
    
    uint256 mintTokenAmount = 0;
    uint256 slotTokenAmount = club.momentConf.mintTotal / club.momentConf.seriesTotal;

    for (uint256 i = 0; i < cardArr.length; i++) {
      uint256 cardNo = cardArr[i];
      uint256 cardAmount = amountArr[i];

      uint256 holdAmount = balanceOf[_msgSender()][clubId][cardNo];
      if (cardAmount == 0 || cardAmount > holdAmount) revert InvalidAmount();
      balanceOf[_msgSender()][clubId][cardNo] = holdAmount - cardAmount;
    
      uint256 supply = cardSupply[clubId][cardNo];
      mintTokenAmount = mintTokenAmount + slotTokenAmount * cardAmount / supply;

      emit MomentCardUpdate(_msgSender(), clubId, cardNo, supply - cardAmount, holdAmount - cardAmount, cardAmount);
    }
 
    // Mint event must happen before nft transfer
    emit MomentTokenMint(clubId, _msgSender(), club.memeAddress, mintTokenAmount);
    
    MemeFT meme = MemeFT(payable(club.memeAddress));
    meme.mint(_msgSender(), mintTokenAmount);
    
    MomentNFT nft = MomentNFT(club.nftAddress);
    for (uint256 i = 0; i < cardArr.length; i++) {
      uint256 cardNo = cardArr[i];
      uint256 cardAmount = amountArr[i];
      for (uint256 j = 0; j < cardAmount; j++) {
        uint256 tokenId = nft.preMint(_msgSender());
        emit MomentNFTMint(clubId, _msgSender(), club.nftAddress, cardNo, tokenId);
      }
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

  function _buyCardImpl(uint256 clubId, uint256 amount, uint256 expectedPrice, uint256 remainFunds) internal {
    if (amount == 0) revert InvalidAmount();
    MomentClub storage club = momentClubs[clubId];
    if (club.clubId == 0) revert MomentClubNotFound();
    if (club.isLocked) revert MomentClubIsLocked();
    
    uint256 actualPrice = getBuyPrice(clubId, amount);
    uint256 protocolFee = getProtocolFee(actualPrice);
    uint256 subjectFee = getSubjectFee(actualPrice);
    uint256 priceAfterFee = actualPrice + protocolFee + subjectFee;
      
    if (priceAfterFee > expectedPrice || priceAfterFee > remainFunds) { 
      revert InsufficientFunds();
    }
    
    club.funds += actualPrice;
    club.supply += amount;
  
    protocolFees += protocolFee;

    _sendFunds(club.creatorAddress, subjectFee);
    _sendFunds(_msgSender(), remainFunds - priceAfterFee);

    _dropCards(club, amount);

    emit MomentClubTrade(
      club.clubId,  
      _msgSender(), 
      club.supply, 
      club.isLocked, 
      amount, 
      true, 
      priceAfterFee
    );

    if (club.isLocked) {
      wantTge(club);
    }
  }
 
  function _dropCards( MomentClub storage club, uint256 amount) internal {
    uint256 clubId = club.clubId;

    for (uint256 i = 1; i <= amount; i++) {
      _rngNumber += 1;
      uint256 rng = uint256(keccak256(abi.encodePacked(block.number, block.timestamp, _msgSender(), _rngNumber, i)));
      uint256 cardNo = 1 + uint256(rng % club.momentConf.seriesTotal);
      if (_orderCards[cardNo] == 0) {
        _orderItems.push(cardNo);
      } 
      _orderCards[cardNo] += 1;
    }

    for (uint256 i = 0; i < _orderItems.length; i++) {
      uint256 cardNo = _orderItems[i];
      uint256 supply = cardSupply[clubId][cardNo];
      uint256 buyAmount = _orderCards[cardNo];
      uint256 holdAmount = balanceOf[_msgSender()][clubId][cardNo];

      balanceOf[_msgSender()][clubId][cardNo] = holdAmount + buyAmount;
      cardSupply[clubId][cardNo] = supply + buyAmount;
      if (supply == 0) {
        seriesSupply[clubId] += 1;
        if (club.momentConf.mintTotal > 0 && (!club.isLocked) && seriesSupply[clubId] >= club.momentConf.seriesTotal) {
          club.isLocked = true;
        }
      }

      emit MomentCardUpdate(_msgSender(), clubId, cardNo, supply + buyAmount, holdAmount + buyAmount, buyAmount);
      delete _orderCards[cardNo];
    }

    delete _orderItems;
  }
  
  function buyCard(uint256 clubId, uint256 amount, uint256 expectedPrice) external payable whenNotPaused nonReentrant { 
    _buyCardImpl(clubId, amount, expectedPrice, msg.value);
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

      emit MomentCardUpdate(_msgSender(), clubId, cardNo, supply - cardAmount, holdAmount - cardAmount, cardAmount);
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
      priceAfterFee
    );  
  }

  function _sendFunds(address beneficiary, uint256 amount) internal {
    if (beneficiary != address(0) && amount > 0) {
      (bool success, ) = beneficiary.call{value: amount}("");
      if (!success) revert UnableToSendFunds();
    }
  }

  function onNFTTransfer(uint256 clubId, address from, address to, uint256 tokenId) external {
    MomentClub storage club = momentClubs[clubId];
    if (club.nftAddress != _msgSender()) revert InvalidNFTSender();
    address memeAddress = momentClubs[clubId].memeAddress; 
    emit MomentNFTTransfer(clubId, memeAddress, _msgSender(), from, to, tokenId);
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
    return keccak256(abi.encodePacked(
      "\x19\x01",
      chainId,
      callId,
      applyer,
      creationFee,
      momentConf.liquidityAmount,
      momentConf.mintTotal,
      momentConf.seriesTotal,  
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
