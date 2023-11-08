// SPDX-License-Identifier: MIT

// for security it is better to lock the version
pragma solidity 0.8.19;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

//import "hardhat/console.sol";

contract TurnupSharesV3 is OwnableUpgradeable, UUPSUpgradeable {
  error InvalidZeroAddress();
  error DuplicateWish();
  error WishNotFound();
  error DuplicateBind();
  error ClaimRewardShouldBeFalse();
  error TransactionFailedDueToPrice();
  error OnlyKeysOwnerCanBuyFirstKey();
  error BoundCannotBeBuiOrSell();
  error InvalidAmount();
  error InsufficientKeys();
  error CannotSellLastKey();
  error ProtocolFeeDestinationNotSet();
  error ProtocolFeePercentNotSet();
  error SubjectFeePercentNotSet();
  error SubjectDoesNotMatch();
  error UnableToSendFunds();
  error UnableToClaimReward();
  error ReserveQuantityTooLarge();
  error WrongAmount();
  error WrongAddress();
  error NotVoteFound();
  error ZeroReservedQuantity();
  error ZeroReservedWish();
  error OwnerCantBeWisher();

  address public protocolFeeDestination;
  uint256 public protocolFeePercent;
  uint256 public subjectFeePercent;

  // SharesSubject => (Holder => Balance)
  mapping(address => mapping(address => uint256)) public sharesBalance;

  // SharesSubject => Supply
  mapping(address => uint256) public sharesSupply;

  // new variables in V3

  mapping(address => address) public authorizedWishes;

  struct WishPass {
    address owner;
    address subject;
    uint256 totalSupply;
    uint256 subjectReward;
    bool isClaimReward;
    uint256 reservedQuantity;
    mapping(address => uint256) balanceOf;
  }
  mapping(address => WishPass) public wishPasses;

  enum SubjectType {
    WISH,
    BIND,
    KEY
  }

  event Trade(
    address indexed trader,
    address indexed subject,
    bool isBuy,
    uint256 shareAmount,
    uint256 ethAmount,
    uint256 protocolEthAmount,
    uint256 subjectEthAmount,
    uint256 supply,
    SubjectType subjectType
  );

  modifier onlyIfSetup() {
    if (protocolFeeDestination == address(0)) revert ProtocolFeeDestinationNotSet();
    if (protocolFeePercent == 0) revert ProtocolFeePercentNotSet();
    if (subjectFeePercent == 0) revert SubjectFeePercentNotSet();
    _;
  }

  function initialize() public initializer {
    __Ownable_init();
    __UUPSUpgradeable_init();
  }

  function _authorizeUpgrade(address _newImplementation) internal virtual override onlyOwner {}

  function getVer() public pure virtual returns (string memory) {
    return "v5.0.0";
  }

  // @dev Set the destination fee
  // @param _feeDestination The address of the destination
  function setFeeDestination(address _feeDestination) public virtual onlyOwner {
    if (_feeDestination == address(0)) revert InvalidZeroAddress();
    protocolFeeDestination = _feeDestination;
  }

  // @dev Set the protocol fee percent
  // @param _feePercent The percent of the protocol fee
  function setProtocolFeePercent(uint256 _feePercent) public virtual onlyOwner {
    protocolFeePercent = _feePercent;
  }

  // @dev Set the subject fee percent
  // @param _feePercent The percent of the subject fee
  function setSubjectFeePercent(uint256 _feePercent) public virtual onlyOwner {
    subjectFeePercent = _feePercent;
  }

  // @dev Get the price of a given amount of shares
  // @param supply The current supply of keys
  // @param amount The amount of keys to buy
  // @return The price of the given amount of keys
  function getPrice(uint256 supply, uint256 amount) public pure virtual returns (uint256) {
    uint256 sum1 = supply == 0 ? 0 : ((supply - 1) * (supply) * (2 * (supply - 1) + 1)) / 6;
    uint256 sum2 = supply == 0 && amount == 1
      ? 0
      : ((supply + amount - 1) * (supply + amount) * (2 * (supply + amount - 1) + 1)) / 6;
    uint256 summation = sum2 - sum1;
    return (summation * 1 ether) / 2000;
  }

  // @dev Get the current supply of shares
  // @param sharesSubject The subject of the shares
  // @return The current supply of shares
  function getSupply(address sharesSubject) public view virtual returns (uint256) {
    if (wishPasses[sharesSubject].owner != address(0)) {
      return wishPasses[sharesSubject].totalSupply;
    } else if (authorizedWishes[sharesSubject] != address(0)) {
      address wisher = authorizedWishes[sharesSubject];
      return wishPasses[wisher].totalSupply;
    } else {
      return sharesSupply[sharesSubject];
    }
  }

  // @dev Get the buy price of a given amount of shares
  // @param sharesSubject The subject of the shares
  // @param amount The amount of shares to buy
  // @return The buy price of the given amount of shares
  function getBuyPrice(address sharesSubject, uint256 amount) public view virtual returns (uint256) {
    uint256 supply = getSupply(sharesSubject);
    return getPrice(supply, amount);
  }

  // @dev Get the sell price of a given amount of shares
  // @param sharesSubject The subject of the shares
  // @param amount The amount of shares to sell
  // @return The sell price of the given amount of shares
  function getSellPrice(address sharesSubject, uint256 amount) public view virtual returns (uint256) {
    uint256 supply = getSupply(sharesSubject);
    if (supply < amount) revert InvalidAmount();
    return getPrice(supply - amount, amount);
  }

  // @dev Get the buy price of a given amount of shares after fees
  // @param sharesSubject The subject of the shares
  // @param amount The amount of shares to buy
  // @return The buy price of the given amount of shares after fees
  function getBuyPriceAfterFee(address sharesSubject, uint256 amount) public view virtual returns (uint256) {
    uint256 price = getBuyPrice(sharesSubject, amount);
    uint256 protocolFee = getProtocolFee(price);
    uint256 subjectFee = getSubjectFee(price);
    return price + protocolFee + subjectFee;
  }

  // @dev Get the sell price of a given amount of shares after fees
  // @param sharesSubject The subject of the shares
  // @param amount The amount of shares to sell
  // @return The sell price of the given amount of shares after fees
  function getSellPriceAfterFee(address sharesSubject, uint256 amount) public view virtual returns (uint256) {
    uint256 price = getSellPrice(sharesSubject, amount);
    uint256 protocolFee = getProtocolFee(price);
    uint256 subjectFee = getSubjectFee(price);
    return price - protocolFee - subjectFee;
  }

  // @dev Get the protocol fee of a given price
  // @param price The price
  function getProtocolFee(uint256 price) public view virtual returns (uint256) {
    return (price * protocolFeePercent) / 1 ether;
  }

  // @dev Get the subject fee of a given price
  // @param price The price
  function getSubjectFee(uint256 price) public view virtual returns (uint256) {
    return (price * subjectFeePercent) / 1 ether;
  }

  // @dev Buy shares for a given subject
  // @param sharesSubject The subject of the shares
  // @param amount The amount of shares to buy
  function buyShares(address sharesSubject, uint256 amount) public payable virtual onlyIfSetup {
    uint256 supply = getSupply(sharesSubject);
    // solhint-disable-next-line reason-string
    if (!(supply > 0 || sharesSubject == msg.sender)) revert OnlyKeysOwnerCanBuyFirstKey();

    uint256 price = getPrice(supply, amount);
    uint256 protocolFee = getProtocolFee(price);
    uint256 subjectFee = getSubjectFee(price);

    // solhint-disable-next-line reason-string
    if (!(msg.value >= price + protocolFee + subjectFee)) revert TransactionFailedDueToPrice();

    SubjectType subjectType;

    if (wishPasses[sharesSubject].owner != address(0)) {
      if (wishPasses[sharesSubject].subject != address(0)) revert BoundCannotBeBuiOrSell();

      subjectType = SubjectType.WISH;
      wishPasses[sharesSubject].totalSupply += amount;
      wishPasses[sharesSubject].balanceOf[msg.sender] += amount;
      wishPasses[sharesSubject].subjectReward += subjectFee;
      _sendBuyFunds(protocolFee, subjectFee, address(0));
    } else if (authorizedWishes[sharesSubject] != address(0)) {
      subjectType = SubjectType.BIND;
      address wisher = authorizedWishes[sharesSubject];
      wishPasses[wisher].totalSupply += amount;
      wishPasses[wisher].balanceOf[msg.sender] += amount;
      _sendBuyFunds(protocolFee, subjectFee, sharesSubject);
    } else {
      subjectType = SubjectType.KEY;
      sharesBalance[sharesSubject][msg.sender] += amount;
      sharesSupply[sharesSubject] += amount;
      _sendBuyFunds(protocolFee, subjectFee, sharesSubject);
    }

    emit Trade(msg.sender, sharesSubject, true, amount, price, protocolFee, subjectFee, supply + amount, subjectType);
  }

  function _sendBuyFunds(uint256 protocolFee, uint256 subjectFee, address sharesSubject) internal {
    (bool success1, ) = protocolFeeDestination.call{value: protocolFee}("");
    bool success2 = true;
    if (sharesSubject != address(0)) {
      (success2, ) = sharesSubject.call{value: subjectFee}("");
    }
    if (!success1 || !success2) revert UnableToSendFunds();
  }

  function _checkBalance(address sharesSubject, uint256 balance, uint256 amount) internal view {
    if (balance < amount) revert InsufficientKeys();
    if (!(sharesSubject != msg.sender || balance > amount)) revert CannotSellLastKey();
  }

  // @dev Sell shares for a given subject
  // @param sharesSubject The subject of the shares
  // @param amount The amount of shares to sell
  function sellShares(address sharesSubject, uint256 amount) public payable virtual onlyIfSetup {
    uint256 supply = getSupply(sharesSubject);
    if (supply <= amount) revert CannotSellLastKey();

    uint256 price = getPrice(supply - amount, amount);
    uint256 protocolFee = getProtocolFee(price);
    uint256 subjectFee = getSubjectFee(price);

    SubjectType subjectType;

    if (wishPasses[sharesSubject].owner != address(0)) {
      if (wishPasses[sharesSubject].subject != address(0)) revert BoundCannotBeBuiOrSell();
      uint256 balance = wishPasses[sharesSubject].balanceOf[msg.sender];
      _checkBalance(sharesSubject, balance, amount);

      subjectType = SubjectType.WISH;
      wishPasses[sharesSubject].totalSupply -= amount;
      wishPasses[sharesSubject].balanceOf[msg.sender] -= amount;
      wishPasses[sharesSubject].subjectReward += subjectFee;

      _sendSellFunds(price, protocolFee, subjectFee, address(0));
    } else if (authorizedWishes[sharesSubject] != address(0)) {
      address wisher = authorizedWishes[sharesSubject];
      uint256 balance = wishPasses[wisher].balanceOf[msg.sender];
      _checkBalance(sharesSubject, balance, amount);

      subjectType = SubjectType.BIND;
      wishPasses[sharesSubject].totalSupply -= amount;
      wishPasses[sharesSubject].balanceOf[msg.sender] -= amount;

      _sendSellFunds(price, protocolFee, subjectFee, sharesSubject);
    } else {
      uint256 balance = sharesBalance[sharesSubject][msg.sender];
      _checkBalance(sharesSubject, balance, amount);

      subjectType = SubjectType.KEY;
      sharesBalance[sharesSubject][msg.sender] -= amount;
      sharesSupply[sharesSubject] -= amount;
      _sendSellFunds(price, protocolFee, subjectFee, sharesSubject);
    }

    emit Trade(msg.sender, sharesSubject, false, amount, price, protocolFee, subjectFee, supply - amount, subjectType);
  }

  function _sendSellFunds(uint256 price, uint256 protocolFee, uint256 subjectFee, address sharesSubject) internal {
    (bool success1, ) = msg.sender.call{value: price - protocolFee - subjectFee}("");
    (bool success2, ) = protocolFeeDestination.call{value: protocolFee}("");
    bool success3 = true;
    if (sharesSubject != address(0)) {
      (success3, ) = sharesSubject.call{value: subjectFee}("");
    }
    if (!success1 || !success2 || !success3) revert UnableToSendFunds();
  }

  // @dev This function is used to buy shares for multiple subjects at once
  //   Limit the elements in the array when calling this function to not
  //   risk to run out of gas
  // @param sharesSubjects The array of subjects to buy shares for
  // @param amounts The array of amounts to buy for each subject
  function batchBuyShares(address[] memory sharesSubjects, uint256[] memory amounts) public virtual {
    if (sharesSubjects.length != amounts.length) revert WrongAmount();
    for (uint256 i = 0; i < sharesSubjects.length; i++) {
      buyShares(sharesSubjects[i], amounts[i]);
    }
  }

  // @dev This function is used to create a new wish
  //   Only the contract owner can execute it.
  // @param wisher The address of the wisher
  // @param reservedQuantity The amount of shares to reserve for the wisher
  function newWishPass(address wisher, uint256 reservedQuantity) external virtual onlyOwner onlyIfSetup {
    if (!(reservedQuantity > 0 && reservedQuantity <= 50)) revert ReserveQuantityTooLarge();
    if (wisher == address(0)) revert InvalidZeroAddress();
    if (wishPasses[wisher].owner != address(0)) revert DuplicateWish();

    wishPasses[wisher].owner = wisher;
    wishPasses[wisher].reservedQuantity = reservedQuantity;
    wishPasses[wisher].totalSupply = reservedQuantity;
  }

  // @dev This function is used to bind a wish to a subject
  //   Only the contract owner can execute it.
  // @param sharesSubject The address of the subject
  // @param wisher The address of the wisher
  function bindWishPass(address sharesSubject, address wisher) external virtual onlyOwner {
    if (!(sharesSubject != address(0) && wisher != address(0))) revert WrongAddress();
    if (wishPasses[wisher].owner != wisher) revert WishNotFound();
    if (authorizedWishes[sharesSubject] != address(0)) revert DuplicateWish();

    wishPasses[wisher].subject = sharesSubject;
    authorizedWishes[sharesSubject] = wisher;

    if (wishPasses[wisher].isClaimReward) revert ClaimRewardShouldBeFalse();
    wishPasses[wisher].isClaimReward = true;

    if (wishPasses[wisher].subjectReward > 0) {
      (bool success, ) = sharesSubject.call{value: wishPasses[wisher].subjectReward}("");
      if (!success) revert UnableToClaimReward();
    }
  }

  // @dev This function is used to claim the reserved wish pass
  //   Only the sharesSubject itself can call this function to make the claim
  function claimReservedWishPass() external payable virtual {
    address sharesSubject = msg.sender;
    if (authorizedWishes[sharesSubject] == address(0)) revert WishNotFound();

    address wisher = authorizedWishes[sharesSubject];
    if (wishPasses[wisher].owner == wisher) revert OwnerCantBeWisher();
    if (wishPasses[wisher].subject != sharesSubject) revert SubjectDoesNotMatch();
    if (wishPasses[wisher].reservedQuantity == 0) revert ZeroReservedQuantity();
    if (wishPasses[wisher].balanceOf[sharesSubject] > 0) revert ZeroReservedWish();

    uint256 amount = wishPasses[wisher].reservedQuantity;
    uint256 price = getPrice(0, amount);
    uint256 protocolFee = getProtocolFee(price);
    uint256 subjectFee = getSubjectFee(price);

    if (!(msg.value >= price + protocolFee + subjectFee)) revert TransactionFailedDueToPrice();

    wishPasses[wisher].reservedQuantity = 0;
    wishPasses[wisher].balanceOf[sharesSubject] = wishPasses[wisher].reservedQuantity;

    _sendBuyFunds(protocolFee, subjectFee, sharesSubject);

    uint256 supply = wishPasses[wisher].totalSupply;
    emit Trade(msg.sender, sharesSubject, true, amount, price, protocolFee, subjectFee, supply, SubjectType.BIND);
  }
}
