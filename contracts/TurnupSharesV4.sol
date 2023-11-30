// SPDX-License-Identifier: MIT

// for security it is better to lock the version
pragma solidity 0.8.19;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

//import "hardhat/console.sol";

contract TurnupSharesV4 is Initializable, OwnableUpgradeable {
  /*
    About ownership and upgradeability

    The smart contract is upgraded by a multi-sig wallet. We are in the process of defining a DAO to manage it.
    The owner is right now a standard wallet, but will be changed to a multi-sig wallet too once the DAO is ready.

    We are not implementing an explicit time-lock process because when
    a bug is discovered (which is the primary reason why we are using upgradeable
    contracts), the speed of response is crucial to avoid disaster.
    For example, the infamous crash of Terra/UST could have been mitigated if they
    did not have to wait for the fixed lockup time before intervening.

    However, if the future DAO decides to implement a time-lock, it will be implemented in a future upgrade.
*/

  // @dev Event emitted when a trade is executed
  event Trade(
    address indexed trader,
    address indexed subject,
    bool isBuy,
    uint256 amount,
    uint256 price,
    uint256 supply,
    SubjectType subjectType
  );

  event WishCreated(address wisher, uint256 reservedQuantity);
  event WishBound(address indexed sharesSubject, address indexed wisher);
  event ProtocolFeeDestinationUpdated(address protocolFeeDestination);
  event ProtocolFeePercentUpdated(uint256 protocolFeePercent);
  event SubjectFeePercentUpdated(uint256 subjectFeePercent);
  event OperatorUpdated(address operator);
  event DAOUpdated(address dao);

  error InvalidZeroAddress();
  error ExistingWish(address wisher);
  error WishAlreadyBound(address wisher);
  error WishNotFound();
  error ClaimRewardShouldBeFalse();
  error TransactionFailedDueToPrice();
  error OnlyKeysOwnerCanBuyFirstKey();
  error BoundCannotBeBuyOrSell();
  error InvalidAmount();
  error InsufficientKeys(uint256 balance);
  error CannotSellLastKey();
  error ProtocolFeeDestinationNotSet();
  error ProtocolFeePercentNotSet();
  error SubjectFeePercentNotSet();
  error SubjectDoesNotMatch(address subject);
  error UnableToSendFunds();
  error UnableToClaimReward();
  error UnableToClaimParkedFees();
  error ReserveQuantityTooLarge();
  error WrongAmount();
  error ZeroReservedQuantity();
  error InvalidWish(address wisher);
  error NotTheOperator();
  error OperatorNotSet();
  error TooManyKeys();
  error CannotMakeASubjectAWish();
  error CannotMakeASubjectABind();
  error SubjectCannotBeAWish();
  error UpgradedAlreadyInitialized();
  error WishExpired();
  error ExpiredWishCanOnlyBeSold();
  error Forbidden();
  error GracePeriodExpired();
  error BoundWish();
  error WishNotExpiredYet();
  error WishAlreadyClosed();
  error DAONotSetup();
  error AlreadyClosed();

  address public protocolFeeDestination;
  uint256 public protocolFeePercent;
  uint256 public subjectFeePercent;

  // SharesSubject => (Holder => Balance)
  mapping(address => mapping(address => uint256)) public sharesBalance;

  // SharesSubject => Supply
  mapping(address => uint256) public sharesSupply;

  // new variables in V4

  // @dev Mapping of authorized wishes
  mapping(address => address) public authorizedWishes;

  // @dev Struct to track a wish pass
  struct WishPass {
    address owner;
    uint256 totalSupply;
    uint256 createdAt;
    address subject;
    bool isClaimReward;
    uint256 reservedQuantity;
    uint256 subjectReward;
    // the fees are not paid immediately, but parked until the wish is bound or expires
    uint256 parkedFees;
    mapping(address => uint256) balanceOf;
  }

  // @dev Mapping of wish passes
  mapping(address => WishPass) public wishPasses;

  // @dev Enum to track the type of subject
  enum SubjectType {
    WISH,
    BIND,
    KEY
  }

  address public operator;

  // the duration of the wish. If the wish subject does not join the system before the deadline, the wish expires
  // and the refund process can be started
  uint256 public constant WISH_EXPIRATION_TIME = 90 days;
  // if the owners do not sell their wishes in the 30 days grace period, the value of the shares is transferred to a DAO wallet and used for community initiatives
  uint256 public constant WISH_DEADLINE_TIME = 30 days;

  // solhint-disable-next-line var-name-mixedcase
  address public DAO;
  // solhint-disable-next-line var-name-mixedcase
  uint256 public DAOBalance;
  uint256 public protocolFees;

  // @dev Modifier to check if the contract is setup
  modifier onlyIfSetup() {
    if (protocolFeeDestination == address(0)) revert ProtocolFeeDestinationNotSet();
    if (protocolFeePercent == 0) revert ProtocolFeePercentNotSet();
    if (subjectFeePercent == 0) revert SubjectFeePercentNotSet();
    _;
  }

  // @dev Modifier to check if the caller is the operator
  modifier onlyOperator() {
    if (operator == address(0)) revert OperatorNotSet();
    if (operator != _msgSender()) revert NotTheOperator();
    _;
  }

  modifier onlyDAO() {
    if ((DAO == address(0) && _msgSender() != owner()) || (DAO != address(0) && _msgSender() != DAO)) revert Forbidden();
    _;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  // @dev Initialize the contract
  function initialize() public initializer {
    __Ownable_init();
  }

  // @dev Set the operator
  // @param _operator The address of the operator
  function setOperator(address _operator) public onlyDAO {
    if (_operator == address(0)) revert InvalidZeroAddress();
    operator = _operator;
    emit OperatorUpdated(_operator);
  }

  // @dev Set the DAO
  // @param _DAO The address of the DAO
  // @notice Initially, only the owner can set the DAO
  //         Later, only the DAO can update itself
  // solhint-disable-next-line var-name-mixedcase
  function setDAO(address dao) public onlyDAO {
    if (dao == address(0)) revert InvalidZeroAddress();
    DAO = dao;
    emit DAOUpdated(dao);
  }

  // @dev Helper to get the version of the contract
  // @return The version of the contract
  function getVer() public pure virtual returns (string memory) {
    return "v4.2.1";
  }

  // @dev Helper to get the balance of a user for a given wish
  // @param sharesSubject The subject of the shares
  // @param user The user to get the balance of
  // @return The balance of the user for the given wish
  function getWishBalanceOf(address sharesSubject, address user) public view returns (uint256) {
    return wishPasses[sharesSubject].balanceOf[user];
  }

  // @dev Set the destination fee
  // @param _feeDestination The address of the destination
  function setFeeDestination(address _feeDestination) public virtual onlyDAO {
    if (_feeDestination == address(0)) revert InvalidZeroAddress();
    protocolFeeDestination = _feeDestination;
    emit ProtocolFeeDestinationUpdated(_feeDestination);
  }

  // @dev Set the protocol fee percent
  // @param _feePercent The percent of the protocol fee
  function setProtocolFeePercent(uint256 _feePercent) public virtual onlyDAO {
    protocolFeePercent = _feePercent;
    emit ProtocolFeePercentUpdated(_feePercent);
  }

  // @dev Set the subject fee percent
  // @param _feePercent The percent of the subject fee
  function setSubjectFeePercent(uint256 _feePercent) public virtual onlyDAO {
    subjectFeePercent = _feePercent;
    emit SubjectFeePercentUpdated(_feePercent);
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

  // @dev Get hold balance of shares
  // @param sharesSubject The subject of the shares
  // @param user The holder of the shares
  // @return The balance of holder
  function getBalanceOf(address sharesSubject, address user) public view virtual returns (uint256) {
    if (wishPasses[sharesSubject].owner != address(0)) {
      return wishPasses[sharesSubject].balanceOf[user];
    } else if (authorizedWishes[sharesSubject] != address(0)) {
      address wisher = authorizedWishes[sharesSubject];
      return wishPasses[wisher].balanceOf[user];
    } else {
      return sharesBalance[sharesSubject][user];
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
  // @notice The function allows to buy 3 types of shares:
  //   - Keys: The shares of the subject
  //   - Wishes: The shares of the wisher who has not joined yet the system
  //   - Authorized Wishes: The shares of the wisher bound to the subject
  // @param sharesSubject The subject of the shares
  // @param amount The amount of shares to buy
  function buyShares(address sharesSubject, uint256 amount) public payable virtual onlyIfSetup {
    (, uint256 excess) = _buyShares(sharesSubject, amount, msg.value, true);
    if (excess > 0) _sendFundsBackIfUnused(excess);
  }

  function _buyShares(
    address sharesSubject,
    uint256 amount,
    uint256 expectedPrice,
    bool revertOnPriceError
  ) internal returns (bool, uint256) {
    if (amount == 0) {
      if (revertOnPriceError) revert InvalidAmount();
      else return (false, expectedPrice);
    }
    uint256 supply = getSupply(sharesSubject);
    // solhint-disable-next-line reason-string
    if (supply == 0 && sharesSubject != _msgSender()) revert OnlyKeysOwnerCanBuyFirstKey();

    uint256 price = getPrice(supply, amount);
    uint256 protocolFee = getProtocolFee(price);
    uint256 subjectFee = getSubjectFee(price);

    // solhint-disable-next-line reason-string
    if (expectedPrice < price + protocolFee + subjectFee) {
      if (revertOnPriceError) revert TransactionFailedDueToPrice();
      else return (false, expectedPrice);
    }

    SubjectType subjectType;

    if (wishPasses[sharesSubject].owner != address(0)) {
      if (wishPasses[sharesSubject].subject != address(0)) revert BoundCannotBeBuyOrSell();
      if (wishPasses[sharesSubject].createdAt + WISH_EXPIRATION_TIME < block.timestamp) revert ExpiredWishCanOnlyBeSold();
      subjectType = SubjectType.WISH;
      wishPasses[sharesSubject].totalSupply += amount;
      wishPasses[sharesSubject].balanceOf[_msgSender()] += amount;
      wishPasses[sharesSubject].subjectReward += subjectFee;
      wishPasses[sharesSubject].parkedFees += protocolFee;
    } else if (authorizedWishes[sharesSubject] != address(0)) {
      subjectType = SubjectType.BIND;
      address wisher = authorizedWishes[sharesSubject];
      wishPasses[wisher].totalSupply += amount;
      wishPasses[wisher].balanceOf[_msgSender()] += amount;
      protocolFees += protocolFee;
      (bool success, ) = sharesSubject.call{value: subjectFee}("");
      if (!success) revert UnableToSendFunds();
    } else {
      subjectType = SubjectType.KEY;
      sharesBalance[sharesSubject][_msgSender()] += amount;
      sharesSupply[sharesSubject] += amount;
      protocolFees += protocolFee;
      (bool success, ) = sharesSubject.call{value: subjectFee}("");
      if (!success) revert UnableToSendFunds();
    }

    emit Trade(_msgSender(), sharesSubject, true, amount, price, supply + amount, subjectType);
    // It returns the excess sent by the user if any
    return (true, expectedPrice - price - protocolFee - subjectFee);
  }

  function _sendFundsBackIfUnused(uint256 amount) internal {
    (bool success, ) = _msgSender().call{value: amount}("");
    // if the transaction fails, to avoid either blocking the process or losing the amount
    if (!success) protocolFees += amount;
  }

  // @dev Check the balance of a given subject and revert if not correct
  // @param sharesSubject The subject of the shares
  // @param balance The balance of the subject
  // @param amount The amount to check
  function _checkBalance(address sharesSubject, uint256 balance, uint256 amount) internal view {
    if (balance < amount) revert InsufficientKeys(balance);
    if (sharesSubject == _msgSender() && balance == amount) revert CannotSellLastKey();
  }

  // @dev Sell shares for a given subject
  // @notice The function allows to sell 3 types of shares:
  //   - Keys: The shares of the subject
  //   - Wishes: The shares of the wisher who has not joined yet the system
  //   - Authorized Wishes: The shares of the wisher bound to the subject
  // @param sharesSubject The subject of the shares
  // @param amount The amount of shares to sell
  function sellShares(address sharesSubject, uint256 amount) public virtual onlyIfSetup {
    if (amount == 0) revert InvalidAmount();
    uint256 supply = getSupply(sharesSubject);
    if (supply <= amount) revert CannotSellLastKey();

    uint256 price = getPrice(supply - amount, amount);
    uint256 protocolFee = getProtocolFee(price);
    uint256 subjectFee = getSubjectFee(price);

    SubjectType subjectType;
    uint256 balance = getBalanceOf(sharesSubject, _msgSender());
    _checkBalance(sharesSubject, balance, amount);

    if (wishPasses[sharesSubject].owner != address(0)) {
      if (wishPasses[sharesSubject].subject != address(0)) revert BoundCannotBeBuyOrSell();
      if (wishPasses[sharesSubject].createdAt + WISH_EXPIRATION_TIME + WISH_DEADLINE_TIME < block.timestamp)
        revert GracePeriodExpired();
      subjectType = SubjectType.WISH;
      wishPasses[sharesSubject].totalSupply -= amount;
      wishPasses[sharesSubject].balanceOf[_msgSender()] -= amount;
      if (wishPasses[sharesSubject].createdAt + WISH_EXPIRATION_TIME < block.timestamp) {
        // since the subject did not bind the wish, the user is not charged for the sale,
        // on the opposite, the seller will have also the unused subjectFee
        // Instead the protocolFee will be collected by the DAO at the end of the grace period
        wishPasses[sharesSubject].subjectReward -= subjectFee;
        (bool success, ) = _msgSender().call{value: price + subjectFee}("");
        if (!success) revert UnableToSendFunds();
      } else {
        wishPasses[sharesSubject].subjectReward += subjectFee;
        wishPasses[sharesSubject].parkedFees += protocolFee;
        _sendSellFunds(price, protocolFee, subjectFee, address(0));
      }
    } else if (authorizedWishes[sharesSubject] != address(0)) {
      subjectType = SubjectType.BIND;
      address wisher = authorizedWishes[sharesSubject];
      wishPasses[wisher].totalSupply -= amount;
      wishPasses[wisher].balanceOf[_msgSender()] -= amount;
      protocolFees += protocolFee;
      _sendSellFunds(price, protocolFee, subjectFee, sharesSubject);
    } else {
      subjectType = SubjectType.KEY;
      sharesBalance[sharesSubject][_msgSender()] -= amount;
      sharesSupply[sharesSubject] -= amount;
      protocolFees += protocolFee;
      _sendSellFunds(price, protocolFee, subjectFee, sharesSubject);
    }

    emit Trade(_msgSender(), sharesSubject, false, amount, price, supply - amount, subjectType);
  }

  // @dev Internal function to send funds when selling shares or wishes
  //   It reverts if any sends fail.
  // @param price The price
  // @param protocolFee The protocol fee
  // @param subjectFee The subject fee
  // @param sharesSubject The subject of the shares
  function _sendSellFunds(uint256 price, uint256 protocolFee, uint256 subjectFee, address sharesSubject) internal {
    (bool success1, ) = _msgSender().call{value: price - protocolFee - subjectFee}("");
    bool success2 = true;
    if (sharesSubject != address(0)) {
      (success2, ) = sharesSubject.call{value: subjectFee}("");
    }
    if (!success1 || !success2) revert UnableToSendFunds();
  }

  // @dev This function is used to buy shares for multiple subjects at once
  //   Limit the elements in the array when calling this function to not
  //   risk to run out of gas
  // @param sharesSubjects The array of subjects to buy shares for
  // @param amounts The array of amounts to buy for each subject
  function batchBuyShares(
    address[] calldata sharesSubjects,
    uint256[] calldata amounts,
    uint256[] calldata expectedPrices
  ) public payable virtual {
    if (sharesSubjects.length != amounts.length || sharesSubjects.length != expectedPrices.length) revert WrongAmount();
    if (sharesSubjects.length > 10) {
      // avoid the risk of going out-of-gas
      revert TooManyKeys();
    }
    uint256 consumed = 0;
    uint256 excesses = 0;
    for (uint256 i = 0; i < sharesSubjects.length; i++) {
      (bool success, uint256 excess) = _buyShares(
        sharesSubjects[i],
        amounts[i],
        expectedPrices[i],
        // Since prices can change, we don't revert on price error to avoid cancelling all the purchases
        false
      );
      if (success) {
        consumed += expectedPrices[i];
      }
      excesses += excess;
    }
    uint256 remain = msg.value - consumed;
    if (remain > excesses) {
      _sendFundsBackIfUnused(msg.value - excesses);
    }
  }

  // @dev This function is used to create a new wish
  //   Only the operator can execute it.
  // @param wisher The address of the wisher
  // @param reservedQuantity The amount of shares to reserve for the wisher
  function newWishPass(address wisher, uint256 reservedQuantity) external virtual onlyOperator {
    if (sharesSupply[wisher] > 0) revert CannotMakeASubjectAWish();
    if (reservedQuantity == 0 || reservedQuantity > 50) revert ReserveQuantityTooLarge();
    if (wisher == address(0)) revert InvalidZeroAddress();
    if (wishPasses[wisher].owner != address(0)) revert ExistingWish(wishPasses[wisher].owner);
    wishPasses[wisher].owner = wisher;
    wishPasses[wisher].reservedQuantity = reservedQuantity;
    wishPasses[wisher].totalSupply = reservedQuantity;
    wishPasses[wisher].createdAt = block.timestamp;
    emit WishCreated(wisher, reservedQuantity);
  }

  // @dev This function is used to bind a wish to a subject
  //   Only the operator can execute it.
  // @param sharesSubject The address of the subject
  // @param wisher The address of the wisher
  function bindWishPass(address sharesSubject, address wisher) external virtual onlyOperator {
    if (sharesSupply[sharesSubject] > 0) revert CannotMakeASubjectABind();
    if (sharesSubject == wisher) revert SubjectCannotBeAWish();
    if (sharesSubject == address(0) || wisher == address(0)) revert InvalidZeroAddress();
    if (wishPasses[wisher].owner != wisher) revert WishNotFound();
    if (wishPasses[wisher].createdAt + WISH_EXPIRATION_TIME < block.timestamp) revert WishExpired();
    if (authorizedWishes[sharesSubject] != address(0)) revert WishAlreadyBound(authorizedWishes[sharesSubject]);

    wishPasses[wisher].subject = sharesSubject;
    authorizedWishes[sharesSubject] = wisher;

    if (wishPasses[wisher].isClaimReward) revert ClaimRewardShouldBeFalse();
    wishPasses[wisher].isClaimReward = true;

    if (wishPasses[wisher].subjectReward > 0) {
      (bool success, ) = sharesSubject.call{value: wishPasses[wisher].subjectReward}("");
      if (!success) revert UnableToClaimReward();
      protocolFees += wishPasses[wisher].parkedFees;
    }
    emit WishBound(sharesSubject, wisher);
  }

  // @dev This function is used to claim the reserved wish pass
  //   Only the sharesSubject itself can call this function to make the claim
  function claimReservedWishPass() external payable virtual {
    address sharesSubject = _msgSender();
    if (authorizedWishes[sharesSubject] == address(0)) revert WishNotFound();
    address wisher = authorizedWishes[sharesSubject];
    if (wishPasses[wisher].owner != wisher) revert InvalidWish(wishPasses[wisher].owner);
    if (wishPasses[wisher].subject != sharesSubject) revert SubjectDoesNotMatch(wishPasses[wisher].subject);
    if (wishPasses[wisher].reservedQuantity == 0) revert ZeroReservedQuantity();
    if (wishPasses[wisher].createdAt + WISH_EXPIRATION_TIME < block.timestamp) revert WishExpired();

    uint256 amount = wishPasses[wisher].reservedQuantity;
    uint256 price = getPrice(0, amount);
    uint256 protocolFee = getProtocolFee(price);
    uint256 subjectFee = getSubjectFee(price);

    if (msg.value < price + protocolFee + subjectFee) revert TransactionFailedDueToPrice();

    wishPasses[wisher].reservedQuantity = 0;
    wishPasses[wisher].balanceOf[sharesSubject] += amount;
    protocolFees += protocolFee;
    (bool success, ) = sharesSubject.call{value: subjectFee}("");
    if (!success) revert UnableToSendFunds();

    uint256 supply = wishPasses[wisher].totalSupply;
    emit Trade(_msgSender(), sharesSubject, true, amount, price, supply, SubjectType.BIND);
  }

  // @dev This function is used withdraw the protocol fees
  function withdrawProtocolFees(uint256 amount) external {
    if (amount == 0) amount = protocolFees;
    if (amount > protocolFees) revert InvalidAmount();
    if (protocolFeeDestination == address(0) || protocolFees == 0) revert Forbidden();
    (bool success, ) = protocolFeeDestination.call{value: protocolFees}("");
    if (success) {
      protocolFees -= amount;
    } else {
      revert UnableToSendFunds();
    }
  }

  // @dev This function is used to close an expired wish
  function closeExpiredWish(address sharesSubject) external {
    if (DAO == address(0)) revert DAONotSetup();
    if (wishPasses[sharesSubject].subject != address(0)) revert BoundWish();
    if (wishPasses[sharesSubject].createdAt + WISH_EXPIRATION_TIME + WISH_DEADLINE_TIME > block.timestamp)
      revert WishNotExpiredYet();
    if (wishPasses[sharesSubject].parkedFees == 0) revert AlreadyClosed();
    DAOBalance +=
      wishPasses[sharesSubject].parkedFees +
      wishPasses[sharesSubject].subjectReward +
      getPrice(0, wishPasses[sharesSubject].totalSupply);
    wishPasses[sharesSubject].parkedFees = 0;
  }

  // @dev This function is used to transfer unused wish fees to the DAO
  function withdrawDAOFunds(uint256 amount) external {
    if (amount == 0) amount = DAOBalance;
    if (amount > DAOBalance) revert InvalidAmount();
    if (protocolFeeDestination == address(0) || protocolFees == 0) revert Forbidden();
    (bool success, ) = protocolFeeDestination.call{value: protocolFees}("");
    if (success) {
      DAOBalance -= amount;
    } else {
      revert UnableToSendFunds();
    }
  }
}
