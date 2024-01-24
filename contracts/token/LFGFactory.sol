// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// Author : Francesco Sullo < francesco@superpower.io>
// (c) Superpower Labs Inc.

import {AddressUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import {SafeMathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import {ValidatableUpgradeable} from "../utils/ValidatableUpgradeable.sol";
import {LFGToken} from "./LFGToken.sol";
import {ICorePool} from "../pool/ICorePool.sol";

//import {console} from "hardhat/console.sol";

contract LFGFactory is Initializable, ValidatableUpgradeable, ReentrancyGuardUpgradeable {
  using AddressUpgradeable for address;
  using SafeMathUpgradeable for uint256;

  event MintRequested(uint256 indexed orderId, uint256 amount, address indexed to, uint256 lockedUntil);
  event MintAndStakeRequested(
    uint256 indexed orderId,
    uint256 amount,
    address indexed to,
    uint256 lockedUntil,
    uint256 stakeLockedUntil
  );
  event MintAndBurnRequested(uint256 indexed orderId, uint256 amount, address indexed to, uint256 lockedUntil);
  event CancelRequest(uint256 indexed orderId, uint256 amount, address indexed account, uint256 lockedUntil);
  event CancelStakeRequest(
    uint256 indexed orderId,
    uint256 amount,
    address indexed account,
    uint256 lockedUntil,
    uint256 stakeLockedUntil
  );
  event CancelBurnRequest(uint256 indexed orderId, uint256 amount, address indexed account, uint256 lockedUntil);
  event OperatorSet(address indexed operator, bool active);
  event DailyMintedAmountsUpdated(uint256 maxDailyMinted);
  event BurnToUnlockMission(address indexed burner, uint256 unlockId, uint256 burnedAmount);
  event BurnByLootFee(address indexed burner, uint256 orderId, uint256 burnedAmount);
  event UpdateStakeLockedUntil(uint256 indexed orderId, uint256 stakeLockedUntil);

  error SignatureExpired();
  error SignatureAlreadyUsed();
  error NotLfg();
  error InvalidDailyMintedAmounts();
  error InvalidDeadline();
  error InvalidVType();
  error CapReachedForTurnUp();
  error CapReachedForOthers();
  error OperatorAlreadySet();
  error OperatorNotSet();
  error NotAuthorized();
  error WrongRequest();
  error PendingRequest();

  // this error should never happen. If it happens, we are in trouble
  error CapReachedForPool();

  struct MintRequest {
    uint64 orderId;
    uint160 amount;
    uint32 lockedUntil;
  }

  struct MintAndStakeRequest {
    uint64 orderId;
    uint160 amount;
    uint32 lockedUntil;
    uint32 requestedAt;
    uint32 stakeLockedUntil;
  }

  struct MintAndBurnRequest {
    uint64 orderId;
    uint160 amount;
    uint32 lockedUntil;
  }

  enum BurnReason {
    UnlockMission,
    LootFee
  }

  enum MintType {
    Mint,
    MintAndStake,
    MintAndBurn
  }

  struct Config {
    uint128 supplyReservedToPool;
    uint128 poolSupply;
    uint128 minted;
    uint128 maxDailyMinted;
    mapping(address operator => bool) operators;
  }

  address public pool;
  Config public config;
  LFGToken public lfg;

  mapping(bytes32 => bool) private _usedSignatures;
  mapping(uint256 => uint256) private _dailyMinted;
  mapping(address => MintRequest) private _mintRequests;
  mapping(address => MintAndStakeRequest) private _mintAndStakeRequests;
  mapping(address => MintAndBurnRequest) private _mintAndBurnRequests;

  modifier onlyOperator() {
    if (!config.operators[_msgSender()]) revert NotAuthorized();
    _;
  }

  modifier onlyPool() {
    if (pool == address(0) || pool != _msgSender()) revert NotAuthorized();
    _;
  }

  function getMintRequest(address account) external view returns (MintRequest memory) {
    return _mintRequests[account];
  }

  function getMintAndStakeRequest(address account) external view returns (MintAndStakeRequest memory) {
    return _mintAndStakeRequests[account];
  }

  function getMintAndBurnRequest(address account) external view returns (MintAndBurnRequest memory) {
    return _mintAndBurnRequests[account];
  }

  function getMaxDailyMinted() public view returns (uint256) {
    return config.maxDailyMinted;
  }

  function getDailyMinted(uint256 day) public view returns (uint256) {
    return _dailyMinted[day];
  }

  function initialize(address lfg_, address[] memory validators_, uint256 maxDailyMinted_) public initializer {
    __Validatable_init();
    lfg = LFGToken(lfg_);
    for (uint256 i = 0; i < validators_.length; i++) {
      updateValidator(validators_[i], true);
    }
    updateDailyMintedAmounts(maxDailyMinted_);
  }

  function initForPool(uint256 amount) public onlyOwner {
    config.supplyReservedToPool = uint128(amount);
  }

  function setPool(address pool_) public onlyOwner {
    if (pool_ == address(0)) revert NoZeroAddress();
    pool = pool_;
  }

  function setOperator(address operator, bool active) public onlyOwner {
    if (active) {
      if (config.operators[operator]) revert OperatorAlreadySet();
      config.operators[operator] = true;
    } else {
      if (!config.operators[operator]) revert OperatorNotSet();
      delete config.operators[operator];
    }
    emit OperatorSet(operator, active);
  }

  function isOperator(address operator) public view returns (bool) {
    return config.operators[operator];
  }

  function updateDailyMintedAmounts(uint256 maxDailyMinted_) public onlyOwner {
    uint256 _lfgMaxSupply = 2 * 10 ** 27;
    if (maxDailyMinted_ > _lfgMaxSupply / 365) revert InvalidDailyMintedAmounts();
    config.maxDailyMinted = uint128(maxDailyMinted_);
    emit DailyMintedAmountsUpdated(maxDailyMinted_);
  }

  function _updateDailyMinted(uint256 amount) internal {
    uint256 today = block.timestamp / 1 days;
    _dailyMinted[today] += amount;
    if (_dailyMinted[today] > config.maxDailyMinted) revert InvalidDailyMintedAmounts();
    config.minted += uint128(amount);
    if (config.minted > lfg.amountReservedToFactory()) revert CapReachedForTurnUp();
  }

  function _validateSignature(
    uint256 timestamp,
    uint256 validFor, // Usually fixed to 2 hours for apply
    bytes32 hash,
    bytes calldata signature
  ) internal {
    if (timestamp < block.timestamp - validFor) revert SignatureExpired();
    if (!signedByValidator(hash, signature)) revert InvalidSignature();
    _saveSignatureAsUsed(signature);
  }

  // this is called by any user, via TurnUp, to apply for minting LFG
  function applyToMintLfg(
    uint256 orderId,
    uint256 amount,
    uint256 lockedUntil, // after the lock-up period expired, tokens can be minted
    uint256 timestamp,
    uint256 validFor, // Usually fixed to 2 hours for apply
    bytes calldata signature
  ) external nonReentrant {
    _validateSignature(
      timestamp,
      validFor,
      hashForApplyToMintLfg(orderId, amount, lockedUntil, false, _msgSender(), timestamp, validFor),
      signature
    );
    // if there are previous completed requests, we mint the tokens before continuing
    (bool pending, , ) = _claimAllPending(_msgSender());
    // it reverts only if there is a pending MintRequest
    if (pending) revert PendingRequest();
    // create a new request
    _mintRequests[_msgSender()] = MintRequest(uint64(orderId), uint160(amount), uint32(lockedUntil));
    emit MintRequested(orderId, amount, _msgSender(), lockedUntil);
  }

  function hashForApplyToMintLfg(
    uint256 orderId,
    uint256 amount,
    uint256 lockedUntil,
    bool forBurn,
    address to,
    uint256 timestamp,
    uint256 validFor
  ) public view returns (bytes32) {
    if (validFor > 1 weeks) revert InvalidDeadline();
    return
      keccak256(abi.encodePacked("\x19\x01", block.chainid, orderId, amount, lockedUntil, forBurn, to, timestamp, validFor));
  }

  function _claimMintLfg(address account) internal returns (bool) {
    bool pending;
    if (_mintRequests[account].lockedUntil > 0) {
      pending = _mintRequests[account].lockedUntil > block.timestamp;
      _updateDailyMinted(_mintRequests[account].amount);
      lfg.mintFromFactory(account, _mintRequests[account].amount);
      delete _mintRequests[account];
    }
    return pending;
  }

  function applyToMintLfgAndStake(
    uint256 orderId,
    uint256 amount,
    uint256 lockedUntil, // after the lock-up period expired, tokens can be staked
    uint256 stakeLockedUntil, // the end of the lock time for the stake
    uint256 timestamp,
    uint256 validFor, // Usually fixed to 2 hours for apply
    bytes calldata signature
  ) external nonReentrant {
    _validateSignature(
      timestamp,
      validFor,
      hashForApplyToMintLfgAndStake(orderId, amount, lockedUntil, stakeLockedUntil, _msgSender(), timestamp, validFor),
      signature
    );
    // we process previous request to mint and stake
    (, bool pending, ) = _claimAllPending(_msgSender());
    // it reverts only if there is a pending MintAndStakeRequest
    if (pending) revert PendingRequest();
    _mintAndStakeRequests[_msgSender()] = MintAndStakeRequest(
      uint64(orderId),
      uint160(amount),
      uint32(block.timestamp),
      uint32(lockedUntil),
      uint32(stakeLockedUntil)
    );
    emit MintAndStakeRequested(orderId, amount, _msgSender(), lockedUntil, stakeLockedUntil);
  }

  function hashForApplyToMintLfgAndStake(
    uint256 orderId,
    uint256 amount,
    uint256 lockedUntil,
    uint256 stakeLockedUntil,
    address to,
    uint256 timestamp,
    uint256 validFor
  ) public view returns (bytes32) {
    if (validFor > 1 weeks) revert InvalidDeadline();
    return
      keccak256(
        abi.encodePacked("\x19\x01", block.chainid, orderId, amount, lockedUntil, stakeLockedUntil, to, timestamp, validFor)
      );
  }

  function _claimMintLfgAndStake(address account) internal returns (bool) {
    bool pending;
    if (_mintAndStakeRequests[account].lockedUntil > 0) {
      uint256 poolMinLockTime = ICorePool(pool).minLockTime();
      if (_mintAndStakeRequests[account].stakeLockedUntil < block.timestamp + poolMinLockTime) {
        // the claim came too late and the stake would revert
        _mintAndStakeRequests[account].stakeLockedUntil = uint32(block.timestamp) + uint32(poolMinLockTime) + 1;
        emit UpdateStakeLockedUntil(_mintAndStakeRequests[account].orderId, _mintAndStakeRequests[account].stakeLockedUntil);
      }
      pending = _mintAndStakeRequests[account].lockedUntil > block.timestamp;
      _updateDailyMinted(_mintAndStakeRequests[account].amount);
      lfg.mintFromFactory(address(this), _mintAndStakeRequests[account].amount);
      lfg.approve(pool, _mintAndStakeRequests[account].amount);
      ICorePool(pool).stakeAfterMint(
        _msgSender(),
        _mintAndStakeRequests[account].amount,
        uint64(_mintAndStakeRequests[account].stakeLockedUntil)
      );
      delete _mintAndStakeRequests[account];
    }
    return pending;
  }

  function applyToMintLfgAndBurn(
    uint256 orderId,
    uint256 amount,
    uint256 lockedUntil, // the end of the lock time for the stake
    uint256 timestamp,
    uint256 validFor, // Usually fixed to 2 hours for apply
    bytes calldata signature
  ) external nonReentrant {
    _validateSignature(
      timestamp,
      validFor,
      hashForApplyToMintLfg(orderId, amount, lockedUntil, true, _msgSender(), timestamp, validFor),
      signature
    );
    (, , bool pending) = _claimAllPending(_msgSender());
    // it reverts only if there is a pending MintAndBurnRequest
    if (pending) revert PendingRequest();
    _mintAndBurnRequests[_msgSender()] = MintAndBurnRequest(uint64(orderId), uint160(amount), uint32(lockedUntil));
    emit MintAndBurnRequested(orderId, amount, _msgSender(), lockedUntil);
  }

  function _claimMintLfgAndBurn(address account) internal returns (bool) {
    bool pending;
    if (_mintAndBurnRequests[account].lockedUntil > 0) {
      pending = _mintAndBurnRequests[account].lockedUntil > block.timestamp;
      lfg.mintFromFactory(_msgSender(), _mintAndBurnRequests[account].amount);
      lfg.burnFromFactory(account, _mintAndBurnRequests[account].amount);
      delete _mintAndBurnRequests[account];
    }
    return pending;
  }

  function _claimAllPending(address account) internal returns (bool, bool, bool) {
    return (_claimMintLfg(account), _claimMintLfgAndStake(account), _claimMintLfgAndBurn(account));
  }

  function claimAllPending() external nonReentrant {
    _claimAllPending(_msgSender());
  }

  function cancelApplicationToMintLfg(uint256 orderId, address account) external nonReentrant {
    if (!config.operators[_msgSender()]) revert NotAuthorized();
    if (_mintRequests[account].orderId != orderId) revert WrongRequest();
    emit CancelRequest(orderId, _mintRequests[account].amount, account, _mintRequests[account].lockedUntil);
    delete _mintRequests[account];
  }

  function cancelApplicationToMintLfgAndStake(uint256 orderId, address account) external nonReentrant {
    if (!config.operators[_msgSender()]) revert NotAuthorized();
    if (_mintAndStakeRequests[account].orderId != orderId) revert WrongRequest();
    emit CancelStakeRequest(
      orderId,
      _mintAndStakeRequests[account].amount,
      account,
      _mintAndStakeRequests[account].lockedUntil,
      _mintAndStakeRequests[account].stakeLockedUntil
    );
    delete _mintAndStakeRequests[account];
  }

  function cancelApplicationToMintLfgAndBurn(uint256 orderId, address account) external nonReentrant {
    if (!config.operators[_msgSender()]) revert NotAuthorized();
    if (_mintAndBurnRequests[account].orderId != orderId) revert WrongRequest();
    emit CancelBurnRequest(orderId, _mintAndBurnRequests[account].amount, account, _mintAndBurnRequests[account].lockedUntil);
    delete _mintAndBurnRequests[account];
  }

  function burnLfg(
    uint256 orderId,
    uint256 amount,
    BurnReason reason,
    uint256 timestamp,
    uint256 validFor,
    bytes calldata signature
  ) external nonReentrant {
    _validateSignature(
      timestamp,
      validFor,
      hashBurnLfg(orderId, _msgSender(), uint8(reason), amount, timestamp, validFor),
      signature
    );
    lfg.burnFromFactory(_msgSender(), amount);
    if (reason == BurnReason.UnlockMission) {
      emit BurnToUnlockMission(_msgSender(), orderId, amount);
    } else if (reason == BurnReason.LootFee) {
      emit BurnByLootFee(_msgSender(), orderId, amount);
    }
  }

  function hashBurnLfg(
    uint256 orderId,
    address account,
    uint8 reason,
    uint256 amount,
    uint256 timestamp,
    uint256 validFor
  ) public view returns (bytes32) {
    if (validFor > 1 weeks) revert InvalidDeadline();
    return keccak256(abi.encodePacked("\x19\x01", block.chainid, account, orderId, reason, amount, timestamp, validFor));
  }

  //  function

  function _saveSignatureAsUsed(bytes memory _signature) internal {
    bytes32 key = bytes32(keccak256(abi.encodePacked(_signature)));
    if (_usedSignatures[key]) revert SignatureAlreadyUsed();
    _usedSignatures[key] = true;
  }

  function isSignatureUsed(bytes memory _signature) public view returns (bool) {
    bytes32 key = bytes32(keccak256(abi.encodePacked(_signature)));
    return _usedSignatures[key];
  }

  function mintByPool(address to, uint256 amount) external onlyPool nonReentrant {
    if (config.poolSupply + amount > config.supplyReservedToPool) revert CapReachedForPool();
    config.poolSupply += uint128(amount);
    lfg.mintFromFactory(to, amount);
  }
}
