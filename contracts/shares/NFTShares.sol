// SPDX-License-Identifier: MIT

// for security it is better to lock the version
pragma solidity 0.8.20;
 
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import {PFPAsset} from "../nft/PFPAsset.sol";
import {LFGToken} from "../token/LFGToken.sol";

contract NFTShares is Initializable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
  using SafeERC20Upgradeable for LFGToken;

  error ProtocolFeeDestinationNotSet();
  error ProtocolFeePercentNotSet();
  error SubjectFeePercentNotSet();
  error InvalidAmount();
  error LFGTokenNotSet();
  error AssetNotFound();
  error AssetNotActive();
  error TransactionFailedDueToPrice();
  error InsufficientToken();
  error UnableToSendFunds(); 
  error Forbidden();

  event SubjectFeePercentUpdate(uint256 feePercent);
  event ProtocolFeePercentUpdate(uint256 feePercent);
  event ProtocolFeeDestinationUpdate(address feeDestination);
  event LFGTokenUpdate(address lfg);

  event NFTSharesTrade(
    address indexed trader,
    address indexed tokenOwner,
    address indexed tokenAddress,
    uint256 tokenId,
    uint256 supply,
    uint256 balance,
    uint256 amount,
    uint256 priceBase,
    uint256 protocolFee,
    uint256 subjectFee,
    bool isBuy
  );

  address public protocolFeeDestination;
  uint256 public protocolFeePercent;
  uint256 public subjectFeePercent;

  LFGToken public lfg;

  uint256 public protocolFees;

  // token address => (TokenId => true|false)
  mapping(address => mapping(uint256 => bool)) public sharesActive;

  // token address => (TokenId => supply)
  mapping(address => mapping(uint256 => uint256)) public sharesSupply;

  struct AssetHoldInfo {
     mapping(address => uint256) holders;
  }
  // token address => (TokenId => (holder address => hold number))
  mapping(address => mapping(uint256 => AssetHoldInfo)) internal _balanceOf;

  function initialize(address protocolFeeDestination_, address lfg_) public initializer {
    __Ownable_init();
    __Pausable_init();
    setSubjectFeePercent(5 ether / 100);  
    setProtocolFeePercent(5 ether / 100); 
    setProtocolFeeDestination(protocolFeeDestination_);
    setLFGToken(lfg_);
  }

  modifier onlyIfSetUp() {
    if (protocolFeeDestination == address(0)) revert ProtocolFeeDestinationNotSet();
    if (protocolFeePercent == 0) revert ProtocolFeePercentNotSet();
    if (subjectFeePercent == 0) revert SubjectFeePercentNotSet();
    if (address(lfg) == address(0)) revert LFGTokenNotSet();
    _;
  }

  function pause() external onlyOwner {
    _pause();
  }

  function unpause() external onlyOwner {
    _unpause();
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

  function setLFGToken(address lfg_) public virtual onlyOwner {
    lfg = LFGToken(lfg_);
    emit LFGTokenUpdate(address(lfg));
  }

  function isActive(address tokenAddress, uint256 tokenId) public view virtual returns(bool) {
    return sharesActive[tokenAddress][tokenId];
  }

  function getSupply(address tokenAddress, uint256 tokenId) public view virtual returns(uint256) {
    return sharesSupply[tokenAddress][tokenId];
  }

  function balanceOf(address tokenAddress, uint256 tokenId, address user) public view returns(uint256) {
    AssetHoldInfo storage hi = _balanceOf[tokenAddress][tokenId];
    return hi.holders[user];
  }

  function getProtocolFee(uint256 price) public view virtual returns (uint256) {
    return (price * protocolFeePercent) / 1 ether;
  }

  function getSubjectFee(uint256 price) public view virtual returns (uint256) {
    return (price * subjectFeePercent) / 1 ether;
  }

  function getPrice(uint256 supply, uint256 amount) public pure virtual returns(uint256) {
    uint256 sum1 = (supply )* (supply + 1) * (2 * (supply) + 1) / 6;
    uint256 sum2 = (supply + amount) * (supply + 1 + amount) * (2 * (supply + amount) + 1) / 6;
    uint256 summation = sum2 - sum1;
    return summation * 1 ether * 5;
  }

  function getBuyPrice(address tokenAddress, uint256 tokenId, uint256 amount) public view virtual returns(uint256) {
    uint256 supply = getSupply(tokenAddress, tokenId);
    return getPrice(supply, amount);
  }

  function getBuyPriceAfterFee(address tokenAddress, uint256 tokenId, uint256 amount) public view virtual returns(uint256) {
    uint256 price = getBuyPrice(tokenAddress, tokenId, amount);
    uint256 protocolFee = getProtocolFee(price);
    uint256 subjectFee = getSubjectFee(price);
    return price + protocolFee + subjectFee;
  }

  function getSellPrice(address tokenAddress, uint256 tokenId, uint256 amount) public view virtual returns(uint256) {
    uint256 supply = getSupply(tokenAddress, tokenId);
    if (supply < amount) revert InvalidAmount();
    return getPrice(supply - amount, amount);
  }

  function getSellPriceAfterFee(address tokenAddress, uint256 tokenId, uint256 amount) public view virtual returns(uint256) {
    uint256 price = getBuyPrice(tokenAddress, tokenId, amount);
    uint256 protocolFee = getProtocolFee(price);
    uint256 subjectFee = getSubjectFee(price);
    return price - protocolFee - subjectFee;
  }

  function buyShares(address tokenAddress, uint256 tokenId, uint256 amount, uint256 expectedPrice) public payable virtual onlyIfSetUp nonReentrant whenNotPaused {
    if (amount == 0) revert InvalidAmount();
    address tokenOwner = PFPAsset(tokenAddress).ownerOf(tokenId);
    if (tokenOwner == address(0)) revert AssetNotFound();
    uint256 supply = getSupply(tokenAddress, tokenId);
    if (!isActive(tokenAddress, tokenId) && supply == 0 && _msgSender() != tokenOwner) revert AssetNotActive();
    
    uint256 priceBase = getPrice(supply, amount);
    uint256 protocolFee = getProtocolFee(priceBase);
    uint256 subjectFee = getSubjectFee(priceBase);
    uint256 priceTotal = priceBase + protocolFee + subjectFee;
    if (expectedPrice < priceTotal) revert TransactionFailedDueToPrice();
    if (lfg.balanceOf(_msgSender()) < priceTotal) revert InsufficientToken();

    lfg.safeTransferFrom(_msgSender(), address(this), priceTotal);
    
    // ^ We ignore failures. If not, a trader can use a smart contract to buy without
    // implementing a receive function. That would cause the call to fail, making impossible
    // for any other to buy over the asset
    lfg.transfer(tokenOwner, subjectFee);
 
    protocolFees += protocolFee;

    sharesSupply[tokenAddress][tokenId] += amount;

    AssetHoldInfo storage hi = _balanceOf[tokenAddress][tokenId];
    hi.holders[_msgSender()] += amount;
    
    if (!isActive(tokenAddress, tokenId)) {
      sharesActive[tokenAddress][tokenId] = true;
    }

    emit NFTSharesTrade(
      _msgSender(), 
      tokenOwner, 
      tokenAddress,
      tokenId,
      supply + amount, 
      hi.holders[_msgSender()],
      amount, 
      priceBase, 
      protocolFee, 
      subjectFee,
      true
    );
  } 

  function sellShares(address tokenAddress, uint256 tokenId, uint256 amount) public payable virtual onlyIfSetUp nonReentrant whenNotPaused {
    if (amount == 0) revert InvalidAmount();
    address tokenOwner = PFPAsset(tokenAddress).ownerOf(tokenId);
    if (tokenOwner == address(0)) revert AssetNotFound(); 
    uint256 holdAmount = balanceOf(tokenAddress, tokenId, _msgSender());
    if (amount > holdAmount) revert InvalidAmount(); 

    uint256 supply = getSupply(tokenAddress, tokenId);
    uint256 priceBase = getPrice(supply - amount, amount);
    uint256 protocolFee = getProtocolFee(priceBase);
    uint256 subjectFee = getSubjectFee(priceBase);

    lfg.safeTransfer(_msgSender(), priceBase - protocolFee - subjectFee);
    
    // ^ We ignore failures. If not, a trader can use a smart contract to sell without
    // implementing a receive function. That would cause the call to fail, making impossible
    // for any other to sell over the asset
    lfg.transfer(tokenOwner, subjectFee);

    protocolFees += protocolFee;
    
    sharesSupply[tokenAddress][tokenId] -= amount;
    
    AssetHoldInfo storage hi = _balanceOf[tokenAddress][tokenId];
    hi.holders[_msgSender()] = holdAmount - amount;
    
    emit NFTSharesTrade(
      _msgSender(), 
      tokenOwner, 
      tokenAddress,
      tokenId,
      supply - amount, 
      holdAmount - amount,
      amount, 
      priceBase, 
      protocolFee, 
      subjectFee,
      false
    );
  }

  function withdrawProtocolFees(uint256 amount) external virtual onlyIfSetUp nonReentrant {
    if (amount == 0) amount = protocolFees;
    if (amount > protocolFees) revert InvalidAmount();
    if (_msgSender() != protocolFeeDestination || protocolFees == 0) revert Forbidden();
    protocolFees -= amount;
    (bool success, ) = protocolFeeDestination.call{value: amount}("");
    if (!success) revert UnableToSendFunds();
  }

  // @dev This empty reserved space is put in place to allow future versions to add new
  // variables without shifting down storage in the inheritance chain.
  // See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps

  uint256[50] private __gap;
}
