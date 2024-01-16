// SPDX-License-Identifier: MIT

// for security it is better to lock the version
pragma solidity 0.8.19;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

//import "hardhat/console.sol";

contract TurnupSharesV4 is Initializable, OwnableUpgradeable {
  /*
    About ownership and upgradeability

    The smart contract is owned by a multi-sig wallet, which is the only one that can upgrade it.
    https://bscscan.com/tx/0xe2622ee5860d2887ff25d2c46d10143803a69660de71cae9bf94d2a62b193a14

    We are in the process of defining a DAO to manage it.

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
  event WishClosed(address indexed sharesSubject);

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
  error NotCloseableOrAlreadyClosed();
  error InsufficientFunds();
  error InvalidWishedPseudoAddress();

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

  // ReentrancyGuard

  uint256 private constant _NOT_ENTERED = 1;
  uint256 private constant _ENTERED = 2;

  uint256 private _status;
  bool private _reentrancyInitialized;

  /**
   * @dev Prevents a contract from calling itself, directly or indirectly.
   * Calling a `nonReentrant` function from another `nonReentrant`
   * function is not supported. It is possible to prevent this from happening
   * by making the `nonReentrant` function external, and making it call a
   * `private` function that does the actual work.
   */
  modifier nonReentrant() {
    _nonReentrantBefore();
    _;
    _nonReentrantAfter();
  }

  function _nonReentrantBefore() private {
    // On the first call to nonReentrant, _status will be _NOT_ENTERED
    // solhint-disable-next-line custom-errors
    require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

    // Any calls to nonReentrant after this point will fail
    _status = _ENTERED;
  }

  function _nonReentrantAfter() private {
    // By storing the original value once again, a refund is triggered (see
    // https://eips.ethereum.org/EIPS/eip-2200)
    _status = _NOT_ENTERED;
  }

  /**
   * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
   * `nonReentrant` function in the call stack.
   */
  function _reentrancyGuardEntered() internal view returns (bool) {
    return _status == _ENTERED;
  }

  function afterUpgrade() external onlyOwner {
    if (!_reentrancyInitialized) {
      _status = _NOT_ENTERED;
      _reentrancyInitialized = true;
    }
  }

  // end ReentrancyGuard

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
    return "v4.3.4";
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
    return (summation * 1 ether) / 100;
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
  function buyShares(address sharesSubject, uint256 amount) public payable virtual onlyIfSetup nonReentrant {
    (, uint256 excess) = _buyShares(sharesSubject, amount, msg.value, true);
    if (excess > 0) _sendFundsBackIfUnused(excess);
  }

  function _buyShares(
    address sharesSubject,
    uint256 amount,
    uint256 expectedPrice,
    bool revertOnPriceError
  ) internal virtual returns (bool, uint256) {
    if (amount == 0) {
      if (revertOnPriceError) revert InvalidAmount();
      else return (false, expectedPrice);
    }
    uint256 supply = getSupply(sharesSubject);
    if (supply == 0 && sharesSubject != _msgSender()) revert OnlyKeysOwnerCanBuyFirstKey();
    uint256 price = getPrice(supply, amount);
    uint256 protocolFee = getProtocolFee(price);
    uint256 subjectFee = getSubjectFee(price);
    if (expectedPrice < price + protocolFee + subjectFee) {
      if (revertOnPriceError) revert TransactionFailedDueToPrice();
      else return (false, expectedPrice);
    }
    if (wishPasses[sharesSubject].owner != address(0)) {
      _buyWish(sharesSubject, supply, amount, price);
    } else if (authorizedWishes[sharesSubject] != address(0)) {
      _buyBind(sharesSubject, supply, amount, price);
    } else {
      _buyKey(sharesSubject, supply, amount, price);
    }
    // It returns the excess sent by the user if any
    return (true, expectedPrice - price - protocolFee - subjectFee);
  }

  function _buyWish(address sharesSubject, uint256 supply, uint256 amount, uint256 price) internal virtual {
    if (wishPasses[sharesSubject].subject != address(0)) revert BoundCannotBeBuyOrSell();
    if (wishPasses[sharesSubject].createdAt + WISH_EXPIRATION_TIME < block.timestamp) revert ExpiredWishCanOnlyBeSold();
    wishPasses[sharesSubject].totalSupply += amount;
    wishPasses[sharesSubject].balanceOf[_msgSender()] += amount;
    wishPasses[sharesSubject].subjectReward += getSubjectFee(price);
    wishPasses[sharesSubject].parkedFees += getProtocolFee(price);
    emit Trade(_msgSender(), sharesSubject, true, amount, price, supply + amount, SubjectType.WISH);
  }

  function _buyBind(address sharesSubject, uint256 supply, uint256 amount, uint256 price) internal virtual {
    address wisher = authorizedWishes[sharesSubject];
    wishPasses[wisher].totalSupply += amount;
    wishPasses[wisher].balanceOf[_msgSender()] += amount;
    protocolFees += getProtocolFee(price);
    emit Trade(_msgSender(), sharesSubject, true, amount, price, supply + amount, SubjectType.BIND);
    (bool success, ) = sharesSubject.call{value: getSubjectFee(price)}("");
    if (!success) revert UnableToSendFunds();
  }

  function _buyKey(address sharesSubject, uint256 supply, uint256 amount, uint256 price) internal virtual {
    sharesBalance[sharesSubject][_msgSender()] += amount;
    sharesSupply[sharesSubject] += amount;
    protocolFees += getProtocolFee(price);
    emit Trade(_msgSender(), sharesSubject, true, amount, price, supply + amount, SubjectType.KEY);
    (bool success, ) = sharesSubject.call{value: getSubjectFee(price)}("");
    if (!success) revert UnableToSendFunds();
  }

  function _sendFundsBackIfUnused(uint256 amount) internal virtual {
    (bool success, ) = _msgSender().call{value: amount}("");
    if (!success) revert UnableToSendFunds();
  }

  // @dev Check the balance of a given subject and revert if not correct
  // @param sharesSubject The subject of the shares
  // @param balance The balance of the subject
  // @param amount The amount to check
  function _checkBalance(address sharesSubject, uint256 balance, uint256 amount) internal view virtual {
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
  function sellShares(address sharesSubject, uint256 amount) public virtual onlyIfSetup nonReentrant {
    if (amount == 0) revert InvalidAmount();
    uint256 supply = getSupply(sharesSubject);
    if (supply <= amount) revert CannotSellLastKey();
    uint256 price = getPrice(supply - amount, amount);
    uint256 balance = getBalanceOf(sharesSubject, _msgSender());
    _checkBalance(sharesSubject, balance, amount);
    if (wishPasses[sharesSubject].owner != address(0)) {
      _sellWish(sharesSubject, supply, amount, price);
    } else if (authorizedWishes[sharesSubject] != address(0)) {
      _sellBind(sharesSubject, supply, amount, price);
    } else {
      _sellKey(sharesSubject, supply, amount, price);
    }
  }

  function _sellWish(address sharesSubject, uint256 supply, uint256 amount, uint256 price) internal virtual {
    uint256 protocolFee = getProtocolFee(price);
    uint256 subjectFee = getSubjectFee(price);
    if (wishPasses[sharesSubject].subject != address(0)) revert BoundCannotBeBuyOrSell();
    if (wishPasses[sharesSubject].createdAt + WISH_EXPIRATION_TIME + WISH_DEADLINE_TIME < block.timestamp)
      revert GracePeriodExpired();
    wishPasses[sharesSubject].totalSupply -= amount;
    wishPasses[sharesSubject].balanceOf[_msgSender()] -= amount;
    emit Trade(_msgSender(), sharesSubject, false, amount, price, supply - amount, SubjectType.WISH);
    if (wishPasses[sharesSubject].createdAt + WISH_EXPIRATION_TIME < block.timestamp) {
      // since the subject did not bind the wish, the user is not charged for the sale,
      // on the opposite, the seller will have also the unused subjectFee
      // Instead the protocolFee will be collected by the DAO at the end of the grace period
      wishPasses[sharesSubject].subjectReward -= subjectFee;
      _sendSellFunds(price + subjectFee, 0, 0, address(0));
    } else {
      // silencing wrong warning
      // solhint-disable-next-line
      wishPasses[sharesSubject].subjectReward += subjectFee;
      // solhint-disable-next-line reentrancy
      wishPasses[sharesSubject].parkedFees += protocolFee;
      // solhint-disable-next-line reentrancy
      _sendSellFunds(price, protocolFee, subjectFee, address(0));
    }
  }

  function _sellBind(address sharesSubject, uint256 supply, uint256 amount, uint256 price) internal virtual {
    uint256 protocolFee = getProtocolFee(price);
    uint256 subjectFee = getSubjectFee(price);
    address wisher = authorizedWishes[sharesSubject];
    wishPasses[wisher].totalSupply -= amount;
    wishPasses[wisher].balanceOf[_msgSender()] -= amount;
    protocolFees += protocolFee;
    emit Trade(_msgSender(), sharesSubject, false, amount, price, supply - amount, SubjectType.BIND);
    _sendSellFunds(price, protocolFee, subjectFee, sharesSubject);
  }

  function _sellKey(address sharesSubject, uint256 supply, uint256 amount, uint256 price) internal virtual {
    uint256 protocolFee = getProtocolFee(price);
    uint256 subjectFee = getSubjectFee(price);
    sharesBalance[sharesSubject][_msgSender()] -= amount;
    sharesSupply[sharesSubject] -= amount;
    protocolFees += protocolFee;
    emit Trade(_msgSender(), sharesSubject, false, amount, price, supply - amount, SubjectType.KEY);
    _sendSellFunds(price, protocolFee, subjectFee, sharesSubject);
  }

  // @dev Internal function to send funds when selling shares or wishes
  //   It reverts if any sends fail.
  // @param price The price
  // @param protocolFee The protocol fee
  // @param subjectFee The subject fee
  // @param sharesSubject The subject of the shares
  function _sendSellFunds(uint256 price, uint256 protocolFee, uint256 subjectFee, address sharesSubject) internal virtual {
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
  ) public payable virtual nonReentrant {
    if (sharesSubjects.length != amounts.length || sharesSubjects.length != expectedPrices.length) revert WrongAmount();
    if (sharesSubjects.length > 10) {
      // avoid the risk of going out-of-gas
      revert TooManyKeys();
    }
    uint256 consumed = 0;
    for (uint256 i = 0; i < sharesSubjects.length; i++) {
      (bool success, uint256 excess) = _buyShares(
        sharesSubjects[i],
        amounts[i],
        expectedPrices[i],
        // Since prices can change, we don't revert on price error to avoid cancelling all the purchases
        false
      );
      if (success) {
        consumed += expectedPrices[i] - excess;
      }
    }
    if (msg.value < consumed) revert InsufficientFunds();
    uint256 remain = msg.value - consumed;
    _sendFundsBackIfUnused(remain);
  }

  // @dev This function is used to create a new wish
  //   Only the operator can execute it.
  // @param wisher The address of the wisher
  // @param reservedQuantity The amount of shares to reserve for the wisher
  function newWishPass(address wisher, uint256 reservedQuantity) external virtual onlyOperator {
    if (uint160(wisher) >= uint160(0x0000000000000100000000000000000000000000)) revert InvalidWishedPseudoAddress();
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
  function bindWishPass(address sharesSubject, address wisher) external virtual onlyOperator nonReentrant {
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
    emit WishBound(sharesSubject, wisher);
    if (wishPasses[wisher].subjectReward > 0) {
      protocolFees += wishPasses[wisher].parkedFees;
      (bool success, ) = sharesSubject.call{value: wishPasses[wisher].subjectReward}("");
      if (!success) revert UnableToClaimReward();
    }
  }

  // @dev This function is used to claim the reserved wish pass
  //   Only the sharesSubject itself can call this function to make the claim
  function claimReservedWishPass() external payable virtual nonReentrant {
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
    if (msg.value < price + protocolFee) revert TransactionFailedDueToPrice();
    wishPasses[wisher].reservedQuantity = 0;
    wishPasses[wisher].balanceOf[sharesSubject] += amount;
    protocolFees += protocolFee;
    uint256 supply = wishPasses[wisher].totalSupply;
    emit Trade(_msgSender(), sharesSubject, true, amount, price, supply, SubjectType.BIND);
    if (msg.value - (price + protocolFee) > 0) {
      _sendFundsBackIfUnused(msg.value - (price + protocolFee));
    }
  }

  // @dev This function is used withdraw the protocol fees
  function withdrawProtocolFees(uint256 amount) external virtual nonReentrant {
    if (amount == 0) amount = protocolFees;
    if (amount > protocolFees) revert InvalidAmount();
    if (_msgSender() != protocolFeeDestination || protocolFeeDestination == address(0) || protocolFees == 0) revert Forbidden();
    protocolFees -= amount;
    (bool success, ) = protocolFeeDestination.call{value: amount}("");
    if (!success) revert UnableToSendFunds();
  }

  // @dev This function is used to close an expired wish
  function closeExpiredWish(address sharesSubject) external virtual onlyDAO {
    if (wishPasses[sharesSubject].subject != address(0)) revert BoundWish();
    if (wishPasses[sharesSubject].createdAt + WISH_EXPIRATION_TIME + WISH_DEADLINE_TIME > block.timestamp)
      revert WishNotExpiredYet();
    if (wishPasses[sharesSubject].parkedFees == 0) revert NotCloseableOrAlreadyClosed();
    uint256 remain;
    if (wishPasses[sharesSubject].totalSupply - wishPasses[sharesSubject].reservedQuantity > 0) {
      remain = getPrice(
        wishPasses[sharesSubject].reservedQuantity,
        wishPasses[sharesSubject].totalSupply - wishPasses[sharesSubject].reservedQuantity
      );
    }
    DAOBalance += wishPasses[sharesSubject].parkedFees + wishPasses[sharesSubject].subjectReward + remain;
    wishPasses[sharesSubject].parkedFees = 0;
    emit WishClosed(sharesSubject);
  }

  // @dev This function is used to transfer unused wish fees to the DAO
  function withdrawDAOFunds(uint256 amount, address beneficiary) external virtual onlyDAO nonReentrant {
    if (DAO == address(0)) revert DAONotSetup();
    if (DAOBalance == 0) revert InsufficientFunds();
    if (beneficiary == address(0)) beneficiary = DAO;
    if (amount == 0) amount = DAOBalance;
    if (amount > DAOBalance) revert InvalidAmount();
    if (_msgSender() != DAO) revert Forbidden();
    DAOBalance -= amount;
    (bool success, ) = beneficiary.call{value: amount}("");
    if (!success) revert UnableToSendFunds();
  }

  // @dev This empty reserved space is put in place to allow future versions to add new
  // variables without shifting down storage in the inheritance chain.
  // See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps

  uint256[50] private __gap;
}
