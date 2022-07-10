//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IVotingRequirements {
  
  /**
   * @notice Returns the multi-sig threshold for the contract
   * @dev Contracts that do not implement roles can use 0 for input
   */
  function votesRequired(bytes32) external returns (uint256);
}