// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IERC7631BaseNFTSkippable {
  function getSkipNFT(address owner) external view returns (bool);

  function setSkipNFT(bool status) external;
}
