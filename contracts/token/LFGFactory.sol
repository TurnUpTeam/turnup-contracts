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
  event CancelRequest(uint256 indexed orderId, uint256 amount, address indexed account, uint256 lockedUntil);
  event OperatorSet(address indexed operator, bool active);
  event DailyMintedAmountsUpdated(uint256 maxDailyMinted);
  event BurnToUnlockMission(address indexed burner, uint256 unlockId, uint256 burnedAmount);
  event BurnByLootFee(address indexed burner, uint256 orderId, uint256 burnedAmount);

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

  // this error should never happen. If it happens, we are in trouble
  error CapReachedForPool();

  struct MintRequest {
    uint64 orderId;
    uint160 amount;
    uint32 lockedUntil;
  }

  enum BurnReason {
    UnlockMission,
    LootFee
  }

  struct PoolConfig {
    uint128 supplyReservedToPool;
    uint128 poolSupply;
    uint128 minted;
    uint128 maxDailyMinted;
    address pool;
    mapping(address operator => bool) operators;
  }

  LFGToken public lfg;

  mapping(bytes32 => bool) private _usedSignatures;
  mapping(uint256 => uint256) private _dailyMinted;
  mapping(address => MintRequest) private _mintRequests;

  PoolConfig public poolConfig;

  modifier onlyOperator() {
    if (!poolConfig.operators[_msgSender()]) revert NotAuthorized();
    _;
  }

  modifier onlyPool() {
    if (poolConfig.pool == address(0) || poolConfig.pool != _msgSender()) revert NotAuthorized();
    _;
  }

  function getMaxDailyMinted() public view returns (uint256) {
    return poolConfig.maxDailyMinted;
  }

  function getDailyMinted(uint256 day) public view returns (uint256) {
    return _dailyMinted[day];
  }

  function initialize(address lfg_, address[] memory validators_, uint256 maxDailyMinted_) public initializer {
    __Validatable_init();
    lfg = LFGToken(lfg_);
    _addInitialValidators(validators_);
    updateDailyMintedAmounts(maxDailyMinted_);
  }

  function initForPool(uint256 amount) public onlyOwner {
    poolConfig.supplyReservedToPool = uint128(amount);
  }

  function setPool(address pool_) public onlyOwner {
    if (pool_ == address(0)) revert NoZeroAddress();
    poolConfig.pool = pool_;
  }

  function setOperator(address operator, bool active) public onlyOwner {
    if (active) {
      if (poolConfig.operators[operator]) revert OperatorAlreadySet();
      poolConfig.operators[operator] = true;
    } else {
      if (!poolConfig.operators[operator]) revert OperatorNotSet();
      delete poolConfig.operators[operator];
    }
    emit OperatorSet(operator, active);
  }

  function isOperator(address operator) public view returns (bool) {
    return poolConfig.operators[operator];
  }

  function _addInitialValidators(address[] memory validators_) internal {
    for (uint256 i = 0; i < validators_.length; i++) {
      updateValidator(validators_[i], true);
    }
  }

  function updateDailyMintedAmounts(uint256 maxDailyMinted_) public onlyOwner {
    uint256 _lfgMaxSupply = 2 * 10 ** 27;
    if (maxDailyMinted_ > _lfgMaxSupply / 365) revert InvalidDailyMintedAmounts();
    poolConfig.maxDailyMinted = uint128(maxDailyMinted_);
    emit DailyMintedAmountsUpdated(maxDailyMinted_);
  }

  function _updateDailyMinted(uint256 amount) internal {
    uint256 today = block.timestamp / 1 days;
    _dailyMinted[today] += amount;
    if (_dailyMinted[today] > poolConfig.maxDailyMinted) revert InvalidDailyMintedAmounts();
    poolConfig.minted += uint128(amount);
    if (poolConfig.minted > lfg.maxSupply() / 2) revert CapReachedForTurnUp();
  }

  // this is called by any user, via TurnUp, to apply for minting LFG
  function applyToMintLfg(
    uint256 orderId,
    uint256 amount,
    uint256 lockedUntil, //  after the lock-up period expired, the tokens are unlocked
    uint256 timestamp,
    uint256 validFor, // Usually fixed to 2 hours for apply
    bytes calldata signature
  ) external nonReentrant {
    if (timestamp < block.timestamp - validFor) revert SignatureExpired();
    if (!signedByValidator(hashLfgApply(orderId, amount, lockedUntil, _msgSender(), timestamp, validFor), signature))
      revert InvalidSignature();
    _saveSignatureAsUsed(signature);
    _updateDailyMinted(amount);
    lfg.mintAndLock(_msgSender(), amount, lockedUntil);
    _mintRequests[_msgSender()] = MintRequest(uint64(orderId), uint160(amount), uint32(lockedUntil));
    emit MintRequested(orderId, amount, _msgSender(), lockedUntil);
  }

  function applyToMintLfgAndStake(
    address staker,
    uint256 orderId,
    uint256 amount,
    uint256 lockedUntil, // the end of the lock time for the stake
    uint256 timestamp,
    uint256 validFor, // Usually fixed to 2 hours for apply
    bytes calldata signature
  ) external nonReentrant {
    if (timestamp < block.timestamp - validFor) revert SignatureExpired();
    if (!signedByValidator(hashLfgApply(orderId, amount, lockedUntil, _msgSender(), timestamp, validFor), signature))
      revert InvalidSignature();
    _saveSignatureAsUsed(signature);
    _updateDailyMinted(amount);
    lfg.mintAndLock(address(this), amount, 0);
    lfg.approve(poolConfig.pool, amount);
    ICorePool(poolConfig.pool).stakeAfterMint(staker, amount, uint64(lockedUntil));
  }

  function cancelApplicationToMintLfg(uint256 orderId, address account) external nonReentrant {
    if (!poolConfig.operators[_msgSender()]) revert NotAuthorized();
    MintRequest memory request = _mintRequests[account];
    if (request.orderId != orderId) revert WrongRequest();
    poolConfig.minted -= uint128(request.amount);
    lfg.revertMint(account, request.amount, request.lockedUntil);
    emit CancelRequest(orderId, request.amount, account, request.lockedUntil);
    delete _mintRequests[account];
  }

  function hashLfgApply(
    uint256 orderId,
    uint256 amount,
    uint256 lockedUntil,
    address to,
    uint256 timestamp,
    uint256 validFor
  ) public view returns (bytes32) {
    if (validFor > 1 weeks) revert InvalidDeadline();
    return keccak256(abi.encodePacked("\x19\x01", block.chainid, orderId, amount, timestamp, validFor, lockedUntil, to));
  }

  function burnLfg(
    uint256 orderId,
    uint256 amount,
    BurnReason reason,
    uint256 timestamp,
    uint256 validFor,
    bytes calldata signature
  ) external nonReentrant {
    if (timestamp < block.timestamp - validFor) revert SignatureExpired();
    if (!signedByValidator(hashBurnLfg(orderId, _msgSender(), uint8(reason), amount, timestamp, validFor), signature))
      revert InvalidSignature();
    _saveSignatureAsUsed(signature);
    lfg.burnTo(_msgSender(), amount);
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
    if (poolConfig.poolSupply + amount > poolConfig.supplyReservedToPool) revert CapReachedForPool();
    poolConfig.poolSupply += uint128(amount);
    lfg.mintAndLock(to, amount, 0);
  }
}
