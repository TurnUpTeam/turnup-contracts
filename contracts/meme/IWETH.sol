// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IWETH {
  function deposit() external payable;

  function withdraw(uint256) external;

  function balanceOf(address) external view returns (uint256);

  function approve(address, uint256) external returns (bool);

  function transfer(address, uint256) external returns (bool);
}
