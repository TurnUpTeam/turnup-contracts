// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {TurnupSharesV4c} from "../TurnupSharesV4c.sol";
import {LFGTokenMock} from "./LFGTokenMock.sol";

contract KeysPoolMock {
  TurnupSharesV4c public turnupShares;
  LFGTokenMock public lfgToken;

  constructor(address turnupShares_, address lfgToken_) {
    turnupShares = TurnupSharesV4c(turnupShares_);
    lfgToken = LFGTokenMock(lfgToken_);
  }

  function getMultiplier(address) public view returns (uint256) {
    // we should return a factor accounting for the price of the keys
    return 10000;
  }

  function claimRewards(address sharesSubject) external {
    uint256 divider = 10000;
    uint256 multiplier = getMultiplier(sharesSubject);
    uint256 rewards = turnupShares.claimRewards(sharesSubject);
    lfgToken.mint(sharesSubject, (rewards * 10 ** 15 * multiplier) / divider);
  }
}
