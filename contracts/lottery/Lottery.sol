// SPDX-License-Identifier: MIT

// for security it is better to lock the version
pragma solidity 0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {AddressUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import {SafeMathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import {LFGToken} from "../token/LFGToken.sol";

contract Lottery is Initializable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for LFGToken;
    
    error InvalidRedPackType();
    error InvalidMinTokenAmount();
    error InvalidMaxPickAmount();
    error InvaildRedPackTokenAmount();
    error InvaildRedPackPickTotal();
    error PendingRequest();
    error InvalidRedPackId();
    error InvaildRedPackTime();
    error NotFoundRedPack();
    error InvalidRedPackData();
    error WithdrawCantBePickable();
    error WithdrawCantBeEmpty();
    error UnableToSendFunds();

    event MinTokenAmountSet(uint256 amount);
    event MaxPickAmountSet(uint32 amount);
    event DepositRedPackRequest(
        uint256 packId,
        RedPackType packType, 
        uint256 tokenAmount, 
        uint32 pickTotal, 
        uint256 startTime, 
        uint256 endTime
    );
    event WithdrawRedPackRequest(
        uint256 packId,
        RedPackType packType,
        uint256 tokenAmount,  
        uint256 tokenBack,
        uint32 pickAmount, 
        uint32 pickTotal
    );

    enum RedPackType {
        TokenLfg,
        TokenMatic
    }

    struct RedPackConfig {
        uint256 packId;
        address account;
        RedPackType packType;
        uint256 tokenAmount;
        uint256 tokenExpend;
        uint32 pickAmount;
        uint32 pickTotal;
        uint256 startTime;
        uint256 endTime;
        mapping(uint256 => bool) pickers;
    }

    uint256 public tokenAmountMin;
    uint32 public pickAmountMax;
    
    LFGToken public lfg;
     
    mapping(address => uint256) public managers;
    mapping(uint256 => RedPackConfig) public redPacks;
    
    function initialize(uint256 tokenAmountMin_, uint32 pickAmountMax_) public initializer {
        __Ownable_init();
        __Pausable_init();   
        
        tokenAmountMin = tokenAmountMin_;
        pickAmountMax = pickAmountMax_;
    }

    function setLFGToken(address lfg_) public onlyOwner whenNotPaused {
        lfg = LFGToken(lfg_);
    }
  
    function setMinTokenAmount(uint256 amount) public onlyOwner {
        if (amount <= 0) revert InvalidMinTokenAmount();
        tokenAmountMin = amount;
        emit MinTokenAmountSet(amount);
    }

    function setMaxPickAmount(uint32 amount) public onlyOwner {
        if (amount <= 0) revert InvalidMaxPickAmount();
        pickAmountMax = amount;
        emit MaxPickAmountSet(amount);
    }

    function isPending(address account) public view returns(bool) {
        uint256 packId = managers[account];
        if (packId == 0) return false;
        if (!isPickable(packId)) return false;
        return true;
    }

    function isPickable(uint256 packId) public view returns(bool) {
        if (redPacks[packId].startTime > block.timestamp) return false;
        if (redPacks[packId].endTime < block.timestamp) return false;
        if (redPacks[packId].pickAmount >= redPacks[packId].pickTotal) return false;
        return true;
    }

    function depositRedPack(
        RedPackType packType_, 
        uint256 tokenAmount_, 
        uint32 pickTotal_, 
        uint256 startTime_, 
        uint256 endTime_
    ) public payable whenNotPaused nonReentrant {
        if (pickTotal_ <= 0 || pickTotal_ > pickAmountMax) revert InvaildRedPackPickTotal();
        if (startTime_ >= endTime_) revert InvaildRedPackTime();
        if (endTime_ < block.timestamp) revert InvaildRedPackTime();
        if (isPending(_msgSender())) revert PendingRequest();

        uint256 packId = getUniqueId();
        if (redPacks[packId].packId != 0) revert InvalidRedPackId();
        
        redPacks[packId].packId = packId;
        redPacks[packId].account = _msgSender();
        redPacks[packId].packType = packType_;
        redPacks[packId].tokenExpend = 0;
        redPacks[packId].pickAmount = 0;
        redPacks[packId].pickTotal = pickTotal_;
        redPacks[packId].startTime = startTime_;
        redPacks[packId].endTime = endTime_;

        managers[_msgSender()] = packId;

        if (packType_ == RedPackType.TokenLfg) {
            _depositLfgRedPack(packId);
            emit DepositRedPackRequest(packId, packType_, tokenAmount_, pickTotal_, startTime_, endTime_);
        } else if (packType_ == RedPackType.TokenMatic) {
            _depositMaticRedPack(packId);
            emit DepositRedPackRequest(packId, packType_, msg.value, pickTotal_, startTime_, endTime_);
        } else {
            revert InvalidRedPackType();
        }
    }

    function _depositLfgRedPack(uint256 packId_) internal {
        uint256 lfgAmount = redPacks[packId_].tokenAmount;
        if (lfgAmount < tokenAmountMin) revert InvaildRedPackTokenAmount();

        redPacks[packId_].tokenAmount = lfgAmount;

        lfg.approve(_msgSender(), lfgAmount);
        lfg.safeTransferFrom(_msgSender(), address(this), lfgAmount);
    }

    function _depositMaticRedPack(uint256 packId_) internal {
        if (msg.value < tokenAmountMin) revert InvaildRedPackTokenAmount();

        redPacks[packId_].tokenAmount = msg.value;
    }

    function withdrawRedPack() external whenNotPaused nonReentrant {
        uint256 packId = managers[_msgSender()];
        if (packId == 0) revert NotFoundRedPack();
        if (redPacks[packId].packId != packId) revert InvalidRedPackData();
        if (isPickable(packId)) revert WithdrawCantBePickable();
        if (redPacks[packId].tokenAmount <= redPacks[packId].tokenExpend) revert WithdrawCantBeEmpty();

        delete managers[_msgSender()];

        uint256 backAmount = redPacks[packId].tokenExpend - redPacks[packId].tokenAmount;
        redPacks[packId].tokenExpend = redPacks[packId].tokenAmount;

        if (redPacks[packId].packType == RedPackType.TokenLfg) {
            lfg.safeTransferFrom(address(this), _msgSender(), backAmount);
        } else if (redPacks[packId].packType == RedPackType.TokenMatic) {
            (bool success, ) = _msgSender().call{value: backAmount}("");
            if (!success) revert UnableToSendFunds();
        } else {
            revert InvalidRedPackData();
        }

        emit WithdrawRedPackRequest(
            packId, 
            redPacks[packId].packType, 
            redPacks[packId].tokenAmount, 
            backAmount,
            redPacks[packId].pickAmount,
            redPacks[packId].pickTotal
        ); 
    }

    function pickRedPack(address account) external whenNotPaused nonReentrant {

    }

    function getUniqueId() public view returns(uint256) {
        bytes32 randBytes = keccak256(abi.encodePacked(block.number, blockhash(block.timestamp), msg.sender));
        return uint256(randBytes);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    uint256[50] private __gap;
}