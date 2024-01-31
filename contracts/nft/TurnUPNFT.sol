// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {PFPAsset} from "./PFPAsset.sol";

contract TurnUPNFT is PFPAsset {
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(string memory name, string memory symbol, string memory tokenUri) public initializer {
    __PFPAsset_init(name, symbol, tokenUri, false);
  }
}
