// SPDX-License-Identifier: MIT

// for security it is better to lock the version
pragma solidity 0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import {LFGToken} from "../token/LFGToken.sol";
import {TurnupSharesV4} from "../shares/TurnupSharesV4.sol";

contract Lottery is Initializable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
  using SafeERC20Upgradeable for LFGToken;

  error InvalidZeroLfg();
  error InvalidNoZeroLfg();
  error InvalidZeroShares();
  error InvalidNoZeroShares();
  error InvalidRedPackTokenTotal();
  error InvalidRedPackPickTotal();
  error InvalidProtocolFeesAmount();
  error Forbidden();
  error NotSubjectHolder();
  error RedPackNotStartYet();
  error RedPackAlreadyEndTime();
  error RedPackPickAlreadyEndPick();
  error RedPackPickAlreadyEndToken();
  error RedPackPickAlreadyClaim();
  error RedPackPickDuplidate();
  error RedPackPickNotHolder();
  error InvalidRedPackId();
  error InvalidRedPackTime();
  error NotFoundRedPack();
  error InvalidRedPackData();
  error UnableToSendFunds();

  event LfgTokenUpdate(address lfg);
  event SharesUpdate(address shares);
  event MinLfgPerPickUpdate(uint256 minValue);
  event MinMaticPerPickUpdate(uint256 minValue);
  event RedPackLifeTimeUpdate(uint256 lifeTime);
  event MaxStartTimeUpdate(uint256 maxStartTime);
  event ProtocolFeePercentUpdate(uint256 feePercent);
  event ProtocolFeeDestinationUpdate(address destination);

  event DepositRedPackRequest(
    uint256 packId,
    RedPackType packType,
    address subject,
    address account,
    uint256 tokenTotal,
    uint256 pickTotal,
    uint256 depositTime,
    uint256 startTime,
    uint256 endTime
  );
  event WithdrawRedPackRequest(uint256 packId, RedPackType packType, uint256 amount);
  event PickRedPackRequest(
    uint256 packId,
    RedPackType packType,
    address account,
    uint256 luckyAmount,
    uint256 tokenTotal,
    uint256 tokenExpend,
    uint256 pickTotal,
    uint256 pickAmount,
    uint256 protocolFee,
    uint256 pickTime
  );

  event WithdrawProtocolFees(RedPackType packType, uint256 amount, uint256 total);

  enum RedPackType {
    TokenLfg,
    TokenMatic
  }

  struct RedPackConfig {
    uint256 packId;
    RedPackType packType;
    address subject;
    address account;
    uint256 tokenTotal;
    uint256 tokenExpend;
    uint32 pickTotal;
    uint32 pickAmount;
    uint256 depositTime;
    uint256 startTime;
    uint256 endTime;
    bool isClaimed;
  }

  uint256 public minLfgPerPick;
  uint256 public minMaticPerPick;
  uint256 public redPackLifeTime;
  uint256 public maxStartTime;
  uint256 public protocolFeePercent;
  address public protocolFeeDestination;
  uint256 public lfgProtocolFees;
  uint256 public maticProtocolFees;

  LFGToken public lfg;
  TurnupSharesV4 public shares;

  mapping(address => mapping(uint256 => bool)) public pickers;
  mapping(uint256 => RedPackConfig) public redPacks;

  function initialize(
    uint256 minLfgPerPick_,
    uint256 minMaticPerPick_,
    uint256 redPackLifeTime_,
    uint256 maxStartTime_,
    uint256 protocolFeePercent_,
    address protocolFeeDestination_
  ) public initializer {
    __Ownable_init();
    __Pausable_init();

    updateMinLfgPerPick(minLfgPerPick_);
    updateMinMaticPerPick(minMaticPerPick_);
    updateRedPackLifeTime(redPackLifeTime_);
    updateMaxStartTime(maxStartTime_);
    updateProtocolFeePercent(protocolFeePercent_);
    updateProtocolFeeDestination(protocolFeeDestination_);
  }

  function setLFGToken(address lfg_) public onlyOwner {
    if (lfg_ == address(0)) revert InvalidZeroLfg();
    if (address(lfg) != address(0)) revert InvalidNoZeroLfg();
    lfg = LFGToken(lfg_);
    emit LfgTokenUpdate(address(lfg));
  }

  function setShares(address shares_) public onlyOwner {
    if (shares_ == address(0)) revert InvalidZeroShares();
    if (address(shares) != address(0)) revert InvalidNoZeroShares();
    shares = TurnupSharesV4(shares_);
    emit SharesUpdate(address(shares));
  }

  function updateMinLfgPerPick(uint256 minLfgPerPick_) public onlyOwner {
    minLfgPerPick = minLfgPerPick_;
    emit MinLfgPerPickUpdate(minLfgPerPick);
  }

  function updateMinMaticPerPick(uint256 minMaticPerPick_) public onlyOwner {
    minMaticPerPick = minMaticPerPick_;
    emit MinMaticPerPickUpdate(minMaticPerPick);
  }

  function updateRedPackLifeTime(uint256 redPackLifeTime_) public onlyOwner {
    redPackLifeTime = redPackLifeTime_;
    emit RedPackLifeTimeUpdate(redPackLifeTime);
  }

  function updateMaxStartTime(uint256 maxStartTime_) public onlyOwner {
    maxStartTime = maxStartTime_;
    emit MaxStartTimeUpdate(maxStartTime);
  }

  function updateProtocolFeePercent(uint256 feePercent_) public onlyOwner {
    protocolFeePercent = feePercent_;
    emit ProtocolFeePercentUpdate(protocolFeePercent);
  }

  function updateProtocolFeeDestination(address feeDestination_) public onlyOwner {
    protocolFeeDestination = feeDestination_;
    emit ProtocolFeeDestinationUpdate(protocolFeeDestination);
  }

  function isHolder(address subject, address account) public view returns (bool) {
    uint256 holdNum = shares.getBalanceOf(subject, account);
    return (holdNum > 0);
  }

  function _checkRedPackConfig(RedPackType packType_, uint256 tokenTotal_, uint32 pickTotal_, uint256 startTime_) internal {
    if (packType_ != RedPackType.TokenLfg && packType_ != RedPackType.TokenMatic) revert InvalidRedPackData();
    if (startTime_ + redPackLifeTime < block.timestamp) revert InvalidRedPackTime();
    if (pickTotal_ <= 0) revert InvalidRedPackPickTotal();

    if (packType_ == RedPackType.TokenLfg) {
      if (tokenTotal_ < pickTotal_ * minLfgPerPick) revert InvalidRedPackTokenTotal();
    } else {
      // RedPackType.TokenMatic
      if (msg.value < pickTotal_ * minMaticPerPick) revert InvalidRedPackTokenTotal();
    }
  }

  function depositRedPack(
    address subject_,
    RedPackType packType_,
    uint256 tokenTotal_,
    uint32 pickTotal_,
    uint256 startTime_
  ) public payable whenNotPaused nonReentrant {
    if (startTime_ == 0) startTime_ = block.timestamp;
    _checkRedPackConfig(packType_, tokenTotal_, pickTotal_, startTime_);

    if (!isHolder(subject_, _msgSender())) revert NotSubjectHolder();

    uint256 packId = getUniqueId();
    if (redPacks[packId].packId != 0) revert InvalidRedPackId();

    redPacks[packId].packId = packId;
    redPacks[packId].packType = packType_;
    redPacks[packId].subject = subject_;
    redPacks[packId].account = _msgSender();
    redPacks[packId].tokenTotal = tokenTotal_;
    redPacks[packId].tokenExpend = 0;
    redPacks[packId].pickTotal = pickTotal_;
    redPacks[packId].pickAmount = 0;
    redPacks[packId].depositTime = block.timestamp;
    redPacks[packId].startTime = startTime_;
    redPacks[packId].endTime = startTime_ + redPackLifeTime;
    redPacks[packId].isClaimed = false;

    if (packType_ == RedPackType.TokenLfg) {
      _transferLfgFrom(_msgSender(), address(this), redPacks[packId].tokenTotal);
    } else if (packType_ == RedPackType.TokenMatic) {
      redPacks[packId].tokenTotal = msg.value;
    }

    emit DepositRedPackRequest(
      redPacks[packId].packId,
      redPacks[packId].packType,
      redPacks[packId].subject,
      redPacks[packId].account,
      redPacks[packId].tokenTotal,
      redPacks[packId].pickTotal,
      redPacks[packId].depositTime,
      redPacks[packId].startTime,
      redPacks[packId].endTime
    );
  }

  function _transferLfgFrom(address from, address to, uint256 amount) internal {
    lfg.approve(from, amount);
    uint256 previousBalance = lfg.balanceOf(from);
    lfg.safeTransferFrom(from, to, amount);
    uint256 newBalance = lfg.balanceOf(from);
    uint256 delta = previousBalance - newBalance;
    if (delta != amount) revert UnableToSendFunds();
  }

  function _transferLfg(address to, uint256 amount) internal {
    lfg.transfer(to, amount);
  }

  function _transferMatic(address to, uint256 amount) internal {
    (bool success, ) = to.call{value: amount}("");
    if (!success) revert UnableToSendFunds();
  }

  function _withdrawRedPack(uint256 packId) internal {
    if (packId == 0) revert NotFoundRedPack();
    if (redPacks[packId].packId != packId) revert InvalidRedPackData();
    if (redPacks[packId].endTime > block.timestamp) return;
    if (redPacks[packId].tokenTotal <= redPacks[packId].tokenExpend) return;
    if (redPacks[packId].isClaimed) return;
    if (redPacks[packId].subject != _msgSender()) return;

    redPacks[packId].isClaimed = true;

    uint256 backAmount = redPacks[packId].tokenTotal - redPacks[packId].tokenExpend;
    redPacks[packId].tokenExpend = redPacks[packId].tokenTotal;

    if (redPacks[packId].packType == RedPackType.TokenLfg) {
      _transferLfg(_msgSender(), backAmount);
    } else if (redPacks[packId].packType == RedPackType.TokenMatic) {
      _transferMatic(_msgSender(), backAmount);
    } else {
      revert InvalidRedPackData();
    }

    emit WithdrawRedPackRequest(packId, redPacks[packId].packType, backAmount);
  }

  function batchWithdrawRedPack(uint256[] calldata packs) public payable whenNotPaused nonReentrant {
    for (uint256 i = 0; i < packs.length; i++) {
      _withdrawRedPack(packs[i]);
    }
  }

  function checkPickable(uint256 packId, address account) public view {
    if (redPacks[packId].packId == 0) revert InvalidRedPackData();
    if (pickers[account][packId]) revert RedPackPickDuplidate(); // pick already
    if (redPacks[packId].pickAmount >= redPacks[packId].pickTotal) revert RedPackPickAlreadyEndPick();
    if (redPacks[packId].isClaimed) revert RedPackPickAlreadyClaim();
    if (redPacks[packId].startTime > block.timestamp) revert RedPackNotStartYet();
    if (redPacks[packId].endTime < block.timestamp) revert RedPackAlreadyEndTime();
    if (redPacks[packId].tokenExpend >= redPacks[packId].tokenTotal) revert RedPackPickAlreadyEndToken();
    if (!isHolder(redPacks[packId].subject, account)) revert RedPackPickNotHolder();
  }

  function pickRedPack(uint256 packId) external whenNotPaused nonReentrant {
    checkPickable(packId, _msgSender());

    uint256 luckyAmount = _randRedPackAmount(packId);
    uint256 protocolFee = (luckyAmount * protocolFeePercent) / 1 ether;

    redPacks[packId].pickAmount += 1;
    redPacks[packId].tokenExpend += luckyAmount;

    pickers[_msgSender()][packId] = true;

    if (redPacks[packId].packType == RedPackType.TokenLfg) {
      lfgProtocolFees += protocolFee;
      _transferLfg(_msgSender(), luckyAmount - protocolFee);
    } else if (redPacks[packId].packType == RedPackType.TokenMatic) {
      maticProtocolFees += protocolFee;
      _transferMatic(_msgSender(), luckyAmount - protocolFee);
    }

    emit PickRedPackRequest(
      packId,
      redPacks[packId].packType,
      _msgSender(),
      luckyAmount - protocolFee,
      redPacks[packId].tokenTotal,
      redPacks[packId].tokenExpend,
      redPacks[packId].pickTotal,
      redPacks[packId].pickAmount,
      protocolFee,
      block.timestamp
    );
  }

  function _randRedPackAmount(uint256 packId) internal view returns (uint256) {
    uint256 remainPick = redPacks[packId].pickTotal - redPacks[packId].pickAmount;
    uint256 remainToken = redPacks[packId].tokenTotal - redPacks[packId].tokenExpend;
    if (remainPick <= 1) {
      return remainToken;
    }
    uint256 minAmount = minLfgPerPick;
    if (redPacks[packId].packType == RedPackType.TokenMatic) {
      minAmount = minMaticPerPick;
    }
    uint256 maxAmount = (remainToken * 2) / remainPick;
    uint256 n = remainToken - minAmount * (remainPick - 1);
    if (maxAmount > n) {
      maxAmount = n;
    }
    uint256 amount = getRandomAmount(minAmount, maxAmount);
    return amount;
  }

  function getRandomAmount(uint256 minAmount, uint256 maxAmount) public view returns (uint256) {
    bytes32 randBytes = keccak256(abi.encodePacked(block.number, blockhash(block.timestamp), _msgSender()));
    return (uint256(randBytes) % (maxAmount - minAmount + 1)) + minAmount;
  }

  function getUniqueId() public view returns (uint256) {
    bytes32 randBytes = keccak256(abi.encodePacked(block.number, blockhash(block.timestamp), _msgSender()));
    return uint256(randBytes);
  }

  function withdrawLfgProtocolFees(uint256 amount) public nonReentrant {
    if (amount == 0) amount = lfgProtocolFees;
    if (amount > lfgProtocolFees) revert InvalidProtocolFeesAmount();
    if (_msgSender() != protocolFeeDestination || protocolFeeDestination == address(0) || lfgProtocolFees == 0)
      revert Forbidden();
    lfgProtocolFees -= amount;
    _transferLfg(protocolFeeDestination, amount);
    emit WithdrawProtocolFees(RedPackType.TokenLfg, amount, lfgProtocolFees);
  }

  function withdrawMaticProtocolFees(uint256 amount) public nonReentrant {
    if (amount == 0) amount = maticProtocolFees;
    if (amount > maticProtocolFees) revert InvalidProtocolFeesAmount();
    if (_msgSender() != protocolFeeDestination || protocolFeeDestination == address(0) || maticProtocolFees == 0)
      revert Forbidden();
    maticProtocolFees -= amount;
    _transferMatic(protocolFeeDestination, amount);
    emit WithdrawProtocolFees(RedPackType.TokenMatic, amount, maticProtocolFees);
  }

  function pause() external onlyOwner {
    _pause();
  }

  function unpause() external onlyOwner {
    _unpause();
  }

  uint256[50] private __gap;
}
