// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ITreasuryV3 {
  //*** EVENTS ***\\
  // Fires when new transaction is submitted
  event TransactionSubmitted(
    uint256 indexed txnID, 
    uint256 indexed accountID, 
    bytes32 indexed requestID,
    address caller, 
    address receiver, 
    uint256 amount, 
    uint256 timestamp
  );
  // Fires when transaction is approved
  event TransactionApproved(
    uint256 indexed txnID, 
    uint256 timestamp
  );
  // Fires when transaction is cancelled by Admin or user
  event TransactionCancelled(
    uint256 indexed txnID, 
    address caller, 
    uint256 timestamp
  );
  // Fires when Admin approves transaction
  event AdminApproved(
    uint256 indexed txnID, 
    address admin, 
    uint256 timestamp
  );
  // Fires when a multi-sig request is submitted
  event RequestSubmitted(
    bytes32 indexed requestID, 
    uint256 indexed txnID, 
    bytes32 indexed role,
    bytes32 funcName,
    bytes32 inputsHash,
    uint256 timestamp
  );
  // Fires when ERC20 token is deposited
  event TokenDeposited(
    bytes32 indexed ticker, 
    uint256 indexed accountID, 
    address indexed tokenAddress,
    uint256 amount, 
    uint256 timestamp
  );

  // Fires when Admin submits ERC20 token addition request
  event ERC20Added(
    bytes32 indexed requestID,
    uint256 indexed txnID, 
    bytes32 indexed ticker, 
    address tokenAddress,
    address adminCaller,
    uint256 timestamp
  );
  // Fires when Admin submits ERC20 token modification request
  event ERC20Modified(
    bytes32 indexed requestID,
    uint256 indexed txnID, 
    bytes32 indexed ticker, 
    address oldAddress, 
    address newAddress, 
    address adminCaller,
    uint256 timestamp
  );
  // Fires when Admin submits an internal transfer
  event InternalTransfer(
    bytes32 indexed requestID,
    uint256 indexed txnID, 
    bytes32 indexed ticker, 
    uint256 amount, 
    uint256 accountFrom, 
    uint256 accountTo, 
    address admin, 
    uint256 timestamp
  );
  // Fires when ETH is deposited via depositETH or receive function
  event ETHDeposited(
    uint256 accountID, 
    uint256 amount, 
    uint256 timestamp
  );

  // Fires when an account role is granted to a user
  event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);

}