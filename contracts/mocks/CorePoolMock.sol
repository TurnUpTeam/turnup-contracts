// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {CorePool} from "../pool/CorePool.sol";

contract CorePoolMock is CorePool{

    uint256 public fakeBlockNumber;
    uint256 public blockNumberAtFake;

    function setFakeBlockNumber(uint256 _fakeBlockNumber) public {
        blockNumberAtFake = block.number;
        fakeBlockNumber = _fakeBlockNumber;
    }

    function blockNumber() public view virtual override returns (uint256) {
        if (fakeBlockNumber > 0) {
            return fakeBlockNumber + block.number - blockNumberAtFake;
        } else {
            return block.number;
        }
    }

}
