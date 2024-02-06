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
import {TurnupSharesV4} from "../shares/TurnupSharesV4.sol";

contract Lottery is Initializable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for LFGToken;
    
    error InvalidZeroLfg();
    error InvalidNoZeroLfg();
    error InvalidZeroShares();
    error InvalidNoZeroShares();
    error InvalidMinLfgPerPick();
    error InvalidMinMaticPerPick();
    error InvalidRedPackType(); 
    error InvaildRedPackTokenTotal();
    error InvaildRedPackPickTotal();
    error NotSubjectHolder();
    error PendingRequest();
    error InvalidRedPackId();
    error InvaildRedPackTime();
    error NotFoundRedPack();
    error InvalidRedPackData();
    error WithdrawCantBePickable();
    error WithdrawCantBeEmpty();
    error UnableToSendFunds();
 
    event DepositRedPackRequest(
        uint256 packId,
        RedPackType packType, 
        address subject,
        address account,
        uint256 tokenTotal,
        uint256 pickTotal,
        uint256 startTime, 
        uint256 endTime
    );
    event WithdrawRedPackRequest(uint256 packId);

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
        uint256 startTime;
        uint256 endTime;
        bool isClaimed;
        mapping(uint256 => bool) pickers;
    }

    uint256 public minLfgPerPick;
    uint256 public minMaticPerPick;
    uint256 public redPackLifeTime;
 
    LFGToken public lfg;
    TurnupSharesV4 public shares;

    mapping(address => mapping(uint256=>uint256)) public pickers;
    mapping(uint256 => RedPackConfig) public redPacks;
    
    function initialize(uint256 minLfgPerPick_, uint256 minMaticPerPick_, uint256 redPackLifeTime_) public initializer {
        __Ownable_init();
        __Pausable_init();   
        
        updateMinLfgPerPick(minLfgPerPick_);
        updateMinMaticPerPick(minMaticPerPick_);
        updateRedPackLifeTime(redPackLifeTime_);
    }

    function setLFGToken(address lfg_) public onlyOwner {
        if (lfg_ == address(0)) revert InvalidZeroLfg();
        if (lfg != address(0)) revert InvalidNoZeroLfg();
        lfg = LFGToken(lfg_);
    }

    function setShares(address shares_) public onlyOwner {
        if (shares_ == address(0)) revert InvalidZeroShares();
        if (shares != address(0)) revert InvalidNoZeroShares();
        shares = TurnupSharesV4(shares_);
    }
  
    function updateMinLfgPerPick(uint256 minLfgPerPick_) public onlyOwner {
        if (minLfgPerPick_ < 100 ether) revert InvalidMinLfgPerTick();
        minLfgPerPick = minLfgPerPick_;
    }

    function updateMinMaticPerPick(uint256 minMaticPerPick_) public onlyOwner {
        if (minMaticPerPick_ < 1 ether / 10) revert InvalidMinMaticPerPick();
        minMaticPerPick = minMaticPerPick_;
    }

    function updateRedPackLifeTime(uint256 redPackLifeTime_) public onlyOwner {
        redPackLifeTime = redPackLifeTime_
    }
  
    function isPickable(uint256 packId, address account) public view returns(bool) {
        if (redPacks[packId].packId == 0) return false
        if (redPacks[packId].startTime > block.timestamp) return false;
        if (redPacks[packId].endTime < block.timestamp) return false;
        if (redPacks[packId].pickAmount >= redPacks[packId].pickTotal) return false;
        if (redPacks[packId].isClaimed) return false;
        if (pickers[account][packId] > 0) return false; // pick already

        if !isHolder() return false;

        return true;
    }

    function isHolder(address subject, address account) public view returns(bool) {
        uint256 holdNum = shares.getBalanceOf(subject, account)
        return holdNum > 0;
    }

    function _checkRedPackConfig internal (
        RedPackType packType_, 
        uint256 tokenTotal_, 
        uint32 pickTotal_, 
        uint256 startTime_) {
        if (packType_ != RedPackType.TokenLfg && packType_ != RedPackType.TokenMatic) revert InvaildRedPackPickTotal();
        if (startTime_ + redPackLifeTime < block.timestamp) revert InvaildRedPackTime();
        if (pickTotal_ <= 0) revert InvaildRedPackPickTotal();
         
        if (packType_ == RedPackType.TokenLfg) {
            if (tokenTotal_ < pickTotal_ * minLfgPerPick) revert InvaildRedPackTokenTotal();    
        } else (packType_ == RedPackType.TokenMatic) {
             if (msg.value < pickTotal_ * minMaticPerPick) revert InvaildRedPackTokenTotal();   
        } else {
            revert InvaildRedPackPickTotal();
        }
    }

    function depositRedPack(
        address subject_,
        RedPackType packType_, 
        uint256 tokenTotal_, 
        uint32 pickTotal_, 
        uint256 startTime_  
    ) public payable whenNotPaused nonReentrant {
        _checkRedPackConfig(packType_, tokenTotal_, pickTotal_, startTime_);
        
        if (!isHolder(subject, _msgSender())) revert NotSubjectHolder();

        uint256 packId = getUniqueId();
        if (redPacks[packId].packId != 0) revert InvalidRedPackId();
        
        redPacks[packId].packId = packId;
        redPacks[packId].packType = packType_;
        redPacks[packId].subject = subject;
        redPacks[packId].account = _msgSender();
        redPacks[packId].tokenTotal = tokenTotal_;
        redPacks[packId].tokenExpend = 0;
        redPacks[packId].pickTotal = pickTotal_;
        redPacks[packId].pickAmount = 0;
        redPacks[packId].startTime = startTime_;
        redPacks[packId].endTime = startTime_ + redPackLifeTime;
 
        if (packType_ == RedPackType.TokenLfg) {
            _depositLfgRedPack(packId);
        } else if (packType_ == RedPackType.TokenMatic) {
            _depositMaticRedPack(packId);
        }  

        emit DepositRedPackRequest(packId, packType_, subject, _msgSender(), 
            redPacks[packId].tokenTotal, pickTotal, startTime, redPacks[packId].endTime);        
    }

    function _depositLfgRedPack(uint256 packId_) internal {
        uint256 lfgTotal = redPacks[packId_].tokenTotal;
        lfg.approve(_msgSender(), lfgAmount);
        lfg.safeTransferFrom(_msgSender(), address(this), lfgAmount);
    }

    function _depositMaticRedPack(uint256 packId_) internal { 
        redPacks[packId_].tokenTotal = msg.value;
    }

    function withdrawRedPack(uint256 packId) public payable whenNotPaused nonReentrant { 
        if (packId == 0) revert NotFoundRedPack();
        if (redPacks[packId].packId != packId) revert InvalidRedPackData();
        if (redPacks[packId].endTime > block.timestamp) return;
        if (redPacks[packId].tokenTotal <= redPacks[packId].tokenExpand) return;
        if (redPacks[packId].isClaimed) return;
        if (redPacks[packId].subject != _msgSender()) return;

        redPacks[packId].isClaimed = true;
 
        uint256 backAmount = redPacks[packId].tokenTotal - redPacks[packId].tokenExpend;
        redPacks[packId].tokenExpend = redPacks[packId].tokenTotal;

        if (redPacks[packId].packType == RedPackType.TokenLfg) {
            lfg.safeTransferFrom(address(this), _msgSender(), backAmount);
        } else if (redPacks[packId].packType == RedPackType.TokenMatic) {
            (bool success, ) = _msgSender().call{value: backAmount}("");
            if (!success) revert UnableToSendFunds();
        } else {
            revert InvalidRedPackData();
        }

        emit WithdrawRedPackRequest(packId); 
    }

    function batchWithdrawRedPack(uint256[] calldata packs) public payable whenNotPaused nonReentrant {
        for (uint256 i = 0; i < packs.length; i++) {
            withdrawRedPack(packs[i]);
        }
    }

    function pickRedPack(uint256 packId) external whenNotPaused nonReentrant {

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