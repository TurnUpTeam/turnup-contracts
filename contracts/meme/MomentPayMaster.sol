// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {Transaction} from "@matterlabs/zksync-contracts/l2/system-contracts/libraries/TransactionHelper.sol";
import {IPaymaster, ExecutionResult, PAYMASTER_VALIDATION_SUCCESS_MAGIC} from "@matterlabs/zksync-contracts/l2/system-contracts/interfaces/IPaymaster.sol";
import {IPaymasterFlow} from "@matterlabs/zksync-contracts/l2/system-contracts/interfaces/IPaymasterFlow.sol";
import {BOOTLOADER_FORMAL_ADDRESS} from "@matterlabs/zksync-contracts/l2/system-contracts/Constants.sol";

contract MomentPayMaster is Initializable, IPaymaster, OwnableUpgradeable, PausableUpgradeable {

    error ZeroAddress();
    error InsufficientFunds();
    error UnableToTransferFunds();
    error MustCallMoment();
    error AllowOnce();

    event WithdrawFunds(address beneficiary, uint256 amount);

    address public momentAddress;
    mapping(address => bool) public books;

    modifier onlyBootloader() {
        require(msg.sender == BOOTLOADER_FORMAL_ADDRESS, "Only bootloader can call this method");
        // Continue execution if called from the bootloader.
        _;
    }

    function initialize() public initializer {
      __Ownable_init();
      __Pausable_init();
    }

    // 1: This is called by the bootloader to check if the paymaster is willing to pay for the transaction
    function validateAndPayForPaymasterTransaction(bytes32, bytes32, Transaction calldata _transaction)
      external payable onlyBootloader whenNotPaused
      returns (bytes4 magic, bytes memory context)
    {
        // By default we consider the transaction as accepted.
        magic = PAYMASTER_VALIDATION_SUCCESS_MAGIC;
        require(_transaction.paymasterInput.length >= 4, "The standard paymaster input must be at least 4 bytes long");

        bytes4 paymasterInputSelector = bytes4(_transaction.paymasterInput[0:4]);

        address fromAddress = address(uint160(_transaction.from));
        address toAddress = address(uint160(_transaction.to));
        
        if (toAddress != momentAddress) {
          revert MustCallMoment();
        }

        if (books[fromAddress]) {
          revert AllowOnce();
        }

        books[fromAddress] = true;

        if (paymasterInputSelector == IPaymasterFlow.general.selector) {
            // Note, that while the minimal amount of ETH needed is tx.gasPrice * tx.gasLimit,
            // neither paymaster nor account are allowed to access this context variable.
            uint256 requiredETH = _transaction.gasLimit *_transaction.maxFeePerGas;

            // The bootloader never returns any data, so it can safely be ignored here.
            (bool success, ) = payable(BOOTLOADER_FORMAL_ADDRESS).call{value: requiredETH}("");
            require(success, "Failed to transfer tx fee to the Bootloader. Paymaster balance might not be enough.");
        } else {
            revert("Unsupported paymaster flow in paymasterParams.");
        }
    }

    // 2: This is called after the transaction (unless it runs out of gas and errors)
    function postTransaction(
        bytes calldata _context,
        Transaction calldata _transaction,
        bytes32 _txHash,
        bytes32 _suggestedSignedHash,
        ExecutionResult _txResult,
        uint256 _maxRefundedGas
    ) external payable onlyBootloader {
    }

    // Needs to be able to receive ETH to pay the bootloader
    receive() external payable {
    }

    function setMomentAddress(address addr) public onlyOwner {
      momentAddress = addr;
    }

    function withdraw(address beneficiary, uint256 amount) public onlyOwner {
      if (beneficiary == address(0)) revert ZeroAddress();
      if (amount == 0) amount = address(this).balance;
      if (amount > address(this).balance) revert InsufficientFunds();

      (bool success, ) = beneficiary.call{value: amount}("");
      if (!success) revert UnableToTransferFunds();

      emit WithdrawFunds(beneficiary, amount);
    }
}
