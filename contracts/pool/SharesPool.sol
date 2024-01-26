// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

import {TurnupSharesV4c} from "../shares/TurnupSharesV4c.sol";
import {LFGToken} from "../token/LFGToken.sol";

contract SharesPool is Ownable2StepUpgradeable, PausableUpgradeable {
  error Forbidden();

  TurnupSharesV4c public turnupShares;
  LFGToken public lfgToken;

  function initialize(address turnupShares_, address lfgToken_) public initializer {
    __Ownable_init();
    __Pausable_init();
    turnupShares = TurnupSharesV4c(turnupShares_);
    lfgToken = LFGToken(lfgToken_);
  }

  function getMultiplier(address) public pure returns (uint256) {
    // we should return a factor accounting for the price of the keys
    return 10000;
  }

  function claimRewards(address sharesSubject) external {
    if (_msgSender() != sharesSubject) revert Forbidden();
    uint256 divider = 10000;
    uint256 multiplier = getMultiplier(sharesSubject);
    uint256 rewards = turnupShares.claimRewards(sharesSubject);
    lfgToken.transfer(sharesSubject, (rewards * 10 ** 15 * multiplier) / divider);
  }

  function pause() external onlyOwner {
    _pause();
  }

  function unpause() external onlyOwner {
    _unpause();
  }

  uint256[50] private __gap;
}
