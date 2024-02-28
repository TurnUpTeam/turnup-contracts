// SPDX-License-Identifier: MIT

// for security it is better to lock the version
pragma solidity 0.8.20;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {SafeERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import {LFGToken} from "../token/LFGToken.sol";

contract LFGAirdropV1 is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
  using SafeERC20Upgradeable for LFGToken;

  error InvalidParameter();
  error InvalidLfgAmount();
  error CantDuplicateDrop();
  error InsufficientLfg();
  error ZeroFundDestiniation();

  event LfgTokenUpdate(address lfg);
  event FundDestinationUpdate(address dest);
  event MaxLfgPerMemberUpdate(uint256 amount);
  event AirdropComplete(address indexed memberAddress, uint256 amount);

  LFGToken public lfg;
  address public fundDestination;

  uint256 public maxLfgPerMember;
  uint256 public dropMemberAmount;

  mapping(address => uint256) public records;

  function initialize() public initializer {
    __Ownable_init();
  }

  function setLfgToken(address lfg_) public onlyOwner {
    if (lfg_ == address(0)) revert InvalidParameter();
    if (address(lfg) != address(0)) revert InvalidParameter();
    lfg = LFGToken(lfg_);
    emit LfgTokenUpdate(address(lfg));
  }

  function setFundDestination(address dest) public onlyOwner {
    if (dest == address(0)) revert InvalidParameter();
    fundDestination = dest;
    emit FundDestinationUpdate(fundDestination);
  }

  function setMaxLfgPerMember(uint256 lfgAmount_) public onlyOwner {
    maxLfgPerMember = lfgAmount_;
    emit MaxLfgPerMemberUpdate(maxLfgPerMember);
  }

  function airdrop(address[] memory memberAddresses, uint256[] memory lfgAmountes) public onlyOwner nonReentrant {
    if (memberAddresses.length == 0) revert InvalidParameter();
    if (memberAddresses.length != lfgAmountes.length) revert InvalidParameter();
    for (uint256 i = 0; i < memberAddresses.length; i++) {
        if (memberAddresses[i] == address(0)) revert InvalidParameter();
        if (lfgAmountes[i] == 0 || lfgAmountes[i] > maxLfgPerMember) revert InvalidLfgAmount();
        if (records[memberAddresses[i]] != 0) revert CantDuplicateDrop();
        if (lfg.balanceOf(address(this)) < lfgAmountes[i]) revert InsufficientLfg();
        records[memberAddresses[i]] = lfgAmountes[i];
        lfg.transfer(memberAddresses[i], lfgAmountes[i]);
        emit AirdropComplete(memberAddresses[i], lfgAmountes[i]);
    }
    dropMemberAmount += memberAddresses.length;
  }

  function getAirdropAmount(address memberAddress) public view returns(uint256) {
    return records[memberAddress];
  }

  function withdrawFunds(uint256 amount) public onlyOwner {
    if (fundDestination == address(0)) revert ZeroFundDestiniation();
    uint256 balance = lfg.balanceOf(address(this));
    if (amount > balance) revert InvalidParameter();
    if (amount == 0) {
        amount = balance;
    }
    lfg.transfer(fundDestination, amount);
  }
  
  uint256[50] private __gap;
}