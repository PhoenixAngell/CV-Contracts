/**
 * @title Crypto Bank
 * @author Phoenix "CryptoPhoenix" Angell
 * @notice An account-based multi-signature smart contract for managing ERC20/ETH balances held by users. Accounts are mapped to user addresses, which require multi-signature approval for withdrawals. This contract set up the design for the Treasury and TreasuryV2 contracts, but is otherwise not a contract the author would ever use.
 * @dev Inherits from WalletAdmins, but would be benefitted by inheriting from OpenZeppelin's AccessControl
 *
 * NOTE: This is in the Scraps directory due to it having no practical use. This contract is an early iteration of what would become the Treasury contracts, but is different enough to stay in this form.
 */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./../WalletAdminsV1-1.sol";
import "./../OpenZeppelinDependencies/IERC20.sol";

contract CryptoBank is WalletAdmins {
  
  /**
   * @notice Withdrawal request struct
   *
   * @param txID ID number of withdrawal
   * @param recipient Recipient's address
   * @param sender Sender requesting withdrawal
   * @param amount Amount of ETH to send
   * @param ticker ERC20 token ticker's keccak256 hash
   * @param approvalStatus Approval status: Submitted, Pending, Approved, Cancelled
   */
  struct txnRequest {
    uint txID;
    address payable recipient;
    address sender;
    uint amount;
    bytes32 ticker;
    APPROVE approvalStatus;
  }

  // Approval status enum
  enum APPROVE { SUBMITTED, PENDING, APPROVED, CANCELLED }

  // Maps user's address to total ETH balance
   // Updated when ETH is deposited or withdrawn
  mapping(address => mapping(bytes32 => uint)) public trueBalance;
  // Maps user's address to their pending balance
   // Updated when transaction is submitted or cancelled
  mapping(address => mapping(bytes32 => uint)) public pendingBalance;

  // Maps a token's keccak256 ticker to its contract address
  mapping(bytes32 => address) public tokenAddress;
  // Maps a token's string ticker to its keccak256 hash
  mapping(string => bytes32) public tokenTicker;

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
  // Fires when user adds a new ERC20 token
  event ERC20Added(string ticker, bytes32 tickerHash, address tokenAddress, uint256 timestamp);

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
   * @param _amount Amount of ERC20 tokens being sent
   * @param _tokenTicker Ticker symbol of ERC20 token being transferred
   */
  function submitTransaction(address payable _recipient, uint _amount, string calldata _tokenTicker) external returns (bool success, uint txID) {
    // Declare local variables
    txID = txnHistory.length;
    address _sender = msg.sender;
    bytes32 tokenTickerBytes = tokenTicker[_tokenTicker];

    // Check pending balance
    require (pendingBalance[msg.sender][tokenTickerBytes] >= _amount, "Insufficient balance");


    // Create new transaction request
    txnRequest memory pendingRequest =
    txnRequest(
              txID,
              _recipient,
              _sender,
              _amount,
              tokenTickerBytes,
              APPROVE.SUBMITTED);

    // Add transaction request to transaction history
    txnHistory.push(pendingRequest);

    // Adjust user's pending balance
     // Note User's true balance is updated when tokens are deposited or transaction is approved
    pendingBalance[msg.sender][tokenTickerBytes] -= _amount;

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
    if(_txnApproval(approvedTxn.txID)) txnApproved = true;
    else txnApproved = false;
  }

  // Tallies up Admin approvals for transaction, performs transaction if multi-sig requirement is met
   // Returns bool flag indicating transaction approval
  function _txnApproval(uint _txID) private returns (bool) {
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
     // Note There's no reason why it should exceed multi-sig requirement, but keep it just in case
    if (numApproved >= adminsRequired) {

      //*** EFFECTS ***\\      
      // Update transaction's approval status to Approved
      txnHistory[_txID].approvalStatus = APPROVE.APPROVED;
      // Update user's true balance
       // Note User's pendingBalance is updated during submission and cancellation
      trueBalance[transaction.sender][transaction.ticker] -= transaction.amount;

      //*** INTERACTIONS ***\\
      // Transfer token to recipient, returns true if successful, false if not
      if(IERC20(tokenAddress[transaction.ticker]).transfer(transaction.recipient, transaction.amount)){
        // Emit approval event
        emit TransactionApproved(_txID, block.timestamp);
        return true;
      }
    }

    // 3. If approvals did not meet multi-sig requirement, then return false flag
    return false;
  }


  // Cancel transaction, only user who submitted transaction or Admins may cancel
  function cancelTransaction(uint _txID) external returns(bool) {
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
    // Update user's pending balance
     // Note User's true balance is updated when ETH is deposited or transaction is approved
    pendingBalance[transaction.sender][transaction.ticker] += transaction.amount;

    // Emit cancellation alert
    emit TransactionCancelled(_txID, msg.sender, block.timestamp);
    return true;
  }

  // Deposits ERC20 token amount, requires approval prior to calling
  function depositToken(string calldata _ticker, uint256 _amount) external payable returns(bool) {
    // Declare local variables
    bytes32 tickerBytes = tokenTicker[_ticker];
    address token = tokenAddress[tickerBytes];

    //*** CHECKS ***\\
    // Check token exists in this contract
    require(token != address(0), "Add token first");
    // Check amount is not zero
    require(_amount != 0, "Amount zero");

    //*** EFFECTS ***\\
    // Update user's balances
    trueBalance[msg.sender][tickerBytes] += _amount;
    pendingBalance[msg.sender][tickerBytes] += _amount;

    //*** INTERACTIONS ***\\
    // Call ERC20 contract's transferFrom
    return(IERC20(token).transferFrom(msg.sender, address(this), _amount));
  }

  // Adds a new ERC20 token to the contract, permissionless
  function addToken(string calldata _ticker, address _tokenAddress) external {
    // Hash token's ticker symbol
    bytes32 tokenTickerBytes = keccak256(abi.encodePacked(_ticker));

    // Check that token doesn't already exist
    require(tokenAddress[tokenTickerBytes] == address(0), "Token exists");

    // Map token ticker symbol to its hash
    tokenTicker[_ticker] = tokenTickerBytes;
    // Map ticker symbol hash to its contract address
    tokenAddress[tokenTickerBytes] = _tokenAddress;

    // Emit alert
    emit ERC20Added(_ticker, tokenTickerBytes, _tokenAddress, block.timestamp);
  }

  // Modifies existing token address data, only Admin may call
  function modifyTokenAddress(string calldata _ticker, address _tokenAddress) external {
    // Check caller is Admin
    require(isAdmin[msg.sender], "Only Admin");

    // Update token contract's address
    tokenAddress[tokenTicker[_ticker]] = _tokenAddress;
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
