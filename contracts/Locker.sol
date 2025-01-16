// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

contract Locker {
	int256 public counter;

  error TestErr();

	event UpdateCounter(address owner, address sender, int256 counter);

  function initialize() public {
  }

 	function GetCounter() public view returns (int256) {
 	  return counter;
 	}

 	function AddCounter(int256 v) public returns (int256){
 	  counter += v;
 	  emit UpdateCounter(address(this), msg.sender, counter);
 	  return counter;
 	}

 	function AddError() public pure {
 	  revert TestErr();
 	}
}