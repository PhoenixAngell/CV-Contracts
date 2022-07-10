/**
 * @title Simple Multi Sig
 * @author Phoenix "CryptoPhoenix" Angell
 * @notice A simple multi-signature smart contract for managing a shared ETH balance.
 * @dev Inherits from WalletAdmins, which allows for adjustable multi-sig requirements.
 * @dev Multi-sig mechanism is internal to this contract.
 */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./WalletAdmins.sol";

contract SimpleMultiSig is WalletAdmins {
  
  /**
   * @notice Withdrawal request struct
   *
   * @param txID ID number of withdrawal
   * @param recipient Recipient's address
   * @param sender Sender requesting withdrawal
   * @param amount Amount of ETH to send
   * @param approvalStatus Approval status: Submitted, Pending, Approved, Cancelled
   */
  struct txnRequest {
    uint txID;
    address payable recipient;
    address sender;
    uint amount;
    APPROVE approvalStatus;
  }

  // Approval status enum
  enum APPROVE { SUBMITTED, PENDING, APPROVED, CANCELLED }


  uint256 public trueBalance;
  uint256 public availableBalance;

  // History of all withdrawal requests:
  txnRequest[] public txnHistory;

  // EVENTS \\
  // Fire when user submits new transaction
  event TransactionSubmitted(uint indexed txID, uint timestamp);
  event TransactionDetails(
    uint indexed txID, 
    address indexed sender, 
    address indexed receiver, 
    uint amount
  );
  // Fires when transaction is approved
  event TransactionApproved(uint indexed txID, uint timestamp);
  // Fires when transaction is cancelled by user or Admin
  event TransactionCancelled(uint indexed txID, address caller, uint timestamp);
  // Fires when Admin approves transaction
  event AdminApproved(uint indexed txID, address admin, uint timestamp);
  // Fires when user deposits ether
  event ETHDeposited(
    address indexed user, 
    uint amount, 
    uint currentBalance, 
    uint availableBalance, 
    uint timestamp
  );

  constructor(
    address[] memory _admins, 
    uint _numerator, 
    uint _denominator
  ) WalletAdmins(_admins, _numerator, _denominator) {
    super;
  }

  // Submits a transaction request
  /**
   * @notice Submits a user's transaction request
   *
   * @param _recipient Transaction recipient
   * @param _amount Amount of wei being sent
   */
  function submitTransaction(address payable _recipient, uint _amount) external returns (bool success, uint txID) {
    // Declare local variables
    txID = txnHistory.length;
    address _sender = msg.sender;

    // Check pending balance
    require (availableBalance >= _amount, "Insufficient balance");


    // Create new transaction request
    txnRequest memory pendingRequest =
    txnRequest(
              txID,
              _recipient,
              _sender,
              _amount,
              APPROVE.SUBMITTED);

    // Add transaction request to transaction history
    txnHistory.push(pendingRequest);

    // Adjust contract's pending balance
    availableBalance -= _amount;

    // Emit events, return success bool
    emit TransactionSubmitted(txID, block.timestamp);
    emit TransactionDetails(txID, msg.sender, _recipient, _amount);
    success = true;
  }

  // Confirm transaction, only Admins may call
  function confirmTransfer(uint _txID) external returns (bool txnApproved) {
    // Declare local variables
    txnRequest memory approvedTxn = txnHistory[_txID];
    APPROVE status = approvedTxn.approvalStatus;
    
    // Check msg.sender has Admin status
    require(isAdmin[msg.sender], "Unauthorized");
    // Check transaction hasn't been approved already
    require(status != APPROVE.APPROVED, "Transaction approved");
    // Check transaction hasn't been cancelled
    require(status != APPROVE.CANCELLED, "Transaction cancelled");
    // Check Admin has not already approved transaction
    require(!adminApproved[msg.sender][_txID], "Admin approved");


    // If txnRequest was Submitted, then set to Pending    
    if(status == APPROVE.SUBMITTED) {
        txnHistory[_txID].approvalStatus = APPROVE.PENDING;
      }
    
    // Update Admin's transaction approval
    adminApproved[msg.sender][_txID] = true;
    // Emit event alert for Admin's approval
    emit AdminApproved(_txID, msg.sender, block.timestamp);
    
    // Run multi-sig check algorithm, return true if transaction is approved, false if not
    if(_txnApproved(approvedTxn.txID)) txnApproved = true;
    else txnApproved = false;
  }

  // Tallies up Admin approvals for transaction, performs transaction if multi-sig requirement is met
  function _txnApproved(uint _txID) private returns (bool) {
    // 0. Initialize local variables
    uint numApproved = 0;
    txnRequest memory transaction = txnHistory[_txID];

    // 1. Iterate through admins array and tally up approvals
    for (uint i = 0; i < admins.length; i++) {
      // Tertiary operator: If Admin approved then increment counter, if not then leave alone
      adminApproved[admins[i]][_txID] ?
        numApproved++ :
        numApproved;
    }

    // 2. If approvals meet or exceed multi-sig requirement, then process transaction and return true flag
    if (numApproved >= adminsRequired) {

      //*** CHECKS ***\\
      require(trueBalance >= transaction.amount, "Insufficient balance");

      //*** EFFECTS ***\\      
      // Update transaction's approval status to Approved
      txnHistory[_txID].approvalStatus = APPROVE.APPROVED;
      // Update contract's current balance
      trueBalance -= transaction.amount;

      //*** INTERACTIONS ***\\
      // Transfer ETH to recipient
      transaction.recipient.transfer(transaction.amount);

      // Emit approval event
      emit TransactionApproved(_txID, block.timestamp);
      // Return true flag
      return true;

    }

    // 3. If approvals did not meet multi-sig requirement, then return false flag
    return false;
  }

  // Cancel transaction, only user who submitted transaction or Admins may cancel
  function cancelTransaction(uint _txID) external {
    // Declare local variables
    txnRequest memory transaction = txnHistory[_txID];

    // Check transaction has not been approved
    require(transaction.approvalStatus != APPROVE.APPROVED, "Txn approved");
    // Check caller is transaction's sender or Admin
    require (
      transaction.sender == msg.sender || 
      isAdmin[msg.sender],
      "Only sender/Admin"
    );

    // Update transaction approval status to Cancelled
    txnHistory[_txID].approvalStatus = APPROVE.CANCELLED;
    // Update contract's pending balance
    availableBalance += transaction.amount;

    // Emit cancellation alert
    emit TransactionCancelled(_txID, msg.sender, block.timestamp);
  }

  // Deposits ETH
  function depositETH() external payable {
    // Check amount is not zero
    require(msg.value != 0, "Amount zero");

    // Update contract's balances
    trueBalance += msg.value;
    availableBalance += msg.value;

    // Emit alert for new deposit
    emit ETHDeposited(
      msg.sender, 
      msg.value, 
      trueBalance, 
      availableBalance, 
      block.timestamp
    );
  }

  // Runs same logic as depositETH, minus the requirement for a non-zero deposit
  receive() external payable {
    // Update contract's balances
    trueBalance += msg.value;
    availableBalance += msg.value;
    
    // Emit alert for new deposit
    emit ETHDeposited(
      msg.sender, 
      msg.value, 
      trueBalance, 
       availableBalance, 
      block.timestamp
    );
  }

  // Returns an error alerting sender that function does not exist
  fallback() external {
    revert("Function does not exist");
  }

  // Returns pending transaction IDs
  function getPending() public view returns (uint[] memory pendingTxnIDs) {
    // 0. Initialize arrayLength variable
    uint arrayLength = 0;

    // 1. Tally number of pending transactions to find arrayLength
    for (uint i = 0; i < txnHistory.length; i++) {
      // Store transaction in local memory
      txnRequest memory transaction = txnHistory[i];

        // If transaction was Approved or Cancelled, then skip to next transaction
        if (
          transaction.approvalStatus == APPROVE.APPROVED ||
          transaction.approvalStatus == APPROVE.CANCELLED
          ) {
            continue;
        }
        // If transaction was not skipped, then increment arrayLength
        arrayLength++;
    }

    // 2. Create, populate, and return a static array of pending transaction IDs
    // 2a. Define size of pendingTxnIDs using arrayLength found in step 1
    pendingTxnIDs = new uint[](arrayLength);

    // 2b. Populate each pendingTxnIDs array element
    for (uint i = 0; i < arrayLength; i++) {
      // Store transaction in local memory
      txnRequest memory transaction = txnHistory[i];

      // If transaction was Approved or Cancelled, then skip to next transaction
      if (
        transaction.approvalStatus == APPROVE.APPROVED ||
        transaction.approvalStatus == APPROVE.CANCELLED
        ) {
          continue;
      }

      // Add transaction ID to pendingTxnIDs
      pendingTxnIDs[i] = transaction.txID;      
    }

    // 3. Return array of txnIDs
    return pendingTxnIDs;
  }

}
