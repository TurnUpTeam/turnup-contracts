// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

// Authors: Francesco Sullo <francesco@sullo.co>

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {AddressUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import {ECDSAUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract ValidatableUpgradeable is Initializable, OwnableUpgradeable {
  using AddressUpgradeable for address;
  using ECDSAUpgradeable for bytes32;

  event ValidatorUpdated(address validator, bool active);

  error ValidatorAlreadySet(address validator);
  error ValidatorNotFound(address validator);
  error NoZeroAddress();
  error InvalidSignature();
  error TooManyValidators();

  struct Validator {
    address validator;
  }

  uint256 private _notFound;
  address[] private _validators;

  // solhint-disable-next-line
  function __Validatable_init() internal onlyInitializing {
    __Ownable_init();
    // we do not allow more than 8 validators to not inflate their number,
    // and to avoid going out of gas while looping over them
    _notFound = 8;
  }

  function _countValidators() internal view returns (uint256) {
    return _validators.length;
  }

  function updateValidator(address validator, bool active) public onlyOwner {
    if (validator == address(0)) revert NoZeroAddress();
    uint256 index = indexOfValidator(validator);
    if (active) {
      if (_countValidators() == _notFound - 1) revert TooManyValidators();
      if (index == _notFound) {
        _validators.push(validator);
      } else {
        revert ValidatorAlreadySet(validator);
      }
    } else {
      if (index == _notFound) {
        revert ValidatorNotFound(validator);
      } else {
        if (_validators.length > 1 && index != _validators.length - 1) {
          _validators[index] = _validators[_validators.length - 1];
        }
        _validators.pop();
      }
    }
    emit ValidatorUpdated(validator, active);
  }

  function indexOfValidator(address validator) public view returns (uint256) {
    for (uint256 i = 0; i < _validators.length; i++) {
      if (_validators[i] == validator) {
        return i;
      }
    }
    return _notFound;
  }

  // this is called internally and externally by the web3 app to test a validation
  function signedByValidator(bytes32 hash, bytes memory signature) public view returns (bool) {
    address signer = hash.recover(signature);
    return indexOfValidator(signer) != _notFound;
  }

  uint256[] private __gap;
}
