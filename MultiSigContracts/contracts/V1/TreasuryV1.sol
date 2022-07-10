/**
 * @title Treasury V1
 * @author Phoenix "CryptoPhoenix" Angell
 * @notice Multi-sig contract used for a development team's treasury reserves. Manages ETH and ERC20 tokens across multiple accounts. This allows setting funds aside for various purposes, all tracked on-chain. Account withdrawals are protected via multi-signature authorization, but administrative functions--such as adding or modifying ERC20 tokens accepted by this contract, or adding new Admins--are handled via the WalletAdmins contract.
 * @notice Funds can be transferred between accounts through an internal transfer, which does not require multi-sig. Transaction requests can be cancelled without multi-sig. Adding/removing Admins is handled by the contract Owner.
 *
 * @dev Every account has two balances, one for the "true" balance and one for the "pending" balance. The true balance is an account's actual internal balance, while the available balance is the balance if all pending transactions are confirmed. This double-balance mechanism prevents over-spending. Transaction requests must be cancelled if funds are needed more urgently elsewhere.
 *
 */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./WalletAdmins.sol";
import "./../OpenZeppelinDependencies/IERC20.sol";

contract TreasuryV1 is WalletAdmins {
  
  /**
   * @notice Withdrawal request struct
   *
   * @param txID ID number of withdrawal
   * @param timestamp Block timestamp when transaction request was submitted
   * @param recipient Recipient's address
   * @param acountID ID of sending account
   * @param amount Amount of ETH to send
   * @param ticker ERC20 token ticker's keccak256 hash
   * @param approvalStatus Approval status: Submitted, Pending, Approved, Cancelled
   */
  struct txnRequest {
    uint256 txID;
    uint256 timestamp;
    uint256 accountID;
    uint256 amount;
    bytes32 ticker;
    address payable recipient;
    APPROVE approvalStatus;
  }

  // Approval status enum
  enum APPROVE { SUBMITTED, PENDING, APPROVED, CANCELLED }

  // Maps account IDs to internal balance
   // Updated when tokens/ETH are deposited or withdrawn
   // Account ID => ticker hash => internal balance
  mapping(uint256 => mapping(bytes32 => uint256)) public trueBalance;
  // Maps account IDs to their pending balances
   // Updated when transactions are submitted or cancelled
   // Used to prevent over-spending before multi-sig vote can finish
   // Account ID => ticker hash => reported balance
  mapping(uint256 => mapping(bytes32 => uint256)) public availableBalance;
  // Maps account IDs to public use permissions
   // Allows non-Admins to interact with / deposit into an account
   // Account ID => public permissions
  mapping(uint256 => bool) public isPublic;

  // Maps a token's keccak256 ticker to its contract address
  mapping(bytes32 => address) public tokenAddress;
  
  // History of all withdrawal requests:
  txnRequest[] public txnHistory;

  // Ticker hash for ether
  bytes32 private ETH;
  // Account that receives ether through receive function
  uint256 public mainAccountID;
  // Tracks number of pending transactions
  uint256 public pendingTxns;

  // EVENTS \\
  // Fire when Admin submits new transaction
  event TransactionSubmitted(uint256 indexed txID, uint256 timestamp);
  event TransactionDetails(
    uint256 indexed txID,
    uint256 indexed accountID, 
    address receiver, 
    uint256 amount
  );
  // Fires when transaction is approved
  event TransactionApproved(uint256 indexed txID, uint256 timestamp);
  // Fires when transaction is cancelled by Admin or user
  event TransactionCancelled(uint256 indexed txID, address caller, uint256 timestamp);
  // Fires when Admin approves transaction
  event AdminApproved(uint256 indexed txID, address admin, uint256 timestamp);
  // Fires when Admin adds a new ERC20 token
  event ERC20Added(
    string indexed ticker, 
    bytes32 tickerHash, 
    address tokenAddress,
    address indexed admin,
    uint256 timestamp
  );
  // Fires when Admin modifies an existing ERC20 token
  event ERC20Modified(
    string indexed ticker, 
    bytes32 tickerHash, 
    address oldAddress, 
    address newAddress, 
    address indexed admin,
    uint256 timestamp
  );
  // Fires when Admin performs an internal transfer
  event InternalTransfer(
    string ticker, 
    uint256 amount, 
    uint256 accountFrom, 
    uint256 accountTo, 
    address admin, 
    uint256 timestamp
  );
  // Fires when ETH is deposited via depositETH or receive function
  event ETHDeposited(uint256 accountID, uint256 amount, uint256 timestamp);


  /**
   * @dev Passing 0 for _numerator is permitted at construction, but once modified
   * cannot be set back to 0. This is to bypass the multi-sig mechanism until the team
   * is ready to activate it.
   *
   * @param _admins Array of all Admins added into WalletAdmins
   * @param _mainAccountID Default account ETH is sent to via receive function
   * @param _tickers Array of ERC20 ticker strings
   * @param _tokenContracts Array of ERC20 token contract addresses
   * @param _numerator Numerator of multi-sig requirement ratio
   * @param _denominator Denominator of multi-sig requirement ratio
   */
  constructor(
    address[] memory _admins, 
    uint256 _mainAccountID,
    string[] memory _tickers,
    address[] memory _tokenContracts,
    uint256 _numerator, 
    uint256 _denominator
  ) WalletAdmins(_admins, _numerator, _denominator) {
    require(_tickers.length == _tokenContracts.length, "Array lengths mismatched");
    super;

    // Add ETH's ticker to contract, using address(this) as its tokenAddress
    ETH = keccak256(abi.encodePacked("ETH"));
    tokenAddress[ETH] = address(this);
    mainAccountID = _mainAccountID; // Main ETH receiving account

    // Upload ERC20 tokens into contract
     // Unchecked because counter variable will never exceed length of _tickers array
    unchecked {
      for(uint256 i = 0; i < _tickers.length; i++){
        // Hash token's ticker string
        bytes32 tokenTickerBytes = keccak256(abi.encodePacked(_tickers[i]));
        
        // Map ticker symbol hash to its contract address
        tokenAddress[tokenTickerBytes] = _tokenContracts[i];

        // Emit ERC20Added alert
        emit ERC20Added(
          _tickers[i], 
          tokenTickerBytes, 
          _tokenContracts[i], 
          msg.sender,
          block.timestamp
        );
      }
    }
  }


  /**
   * @notice Handles logic for permissioned/permissionless accounts
   * @dev Used for depositing tokens and submitting transfer requests, which
   * may sometimes be placed by users in some conditions.
   */
  modifier checkAccountPermissions(uint256 _accountID) {
    if(isPublic[_accountID]){
      _;
    }
    else{
      require(isAdmin[msg.sender], "Only Admin");
      _;
    }
  }

  /**
   * @notice Used for hashing ticker strings without storing on-chain
   */
  function tickerHash(string calldata _ticker) public pure returns (bytes32) {
    return keccak256(abi.encodePacked(_ticker));
  }

  /**
   * @notice Submits a transaction request
   *
   * @param _accountID ID of account to withdraw from
   * @param _recipient Transaction recipient
   * @param _amount Amount of tokens/ETH being sent
   * @param _tokenTicker Ticker symbol of token/ETH being transferred

    UNIT TESTS:
    it("Should not submit a transaction greater than its pending balance")
    it("Should add the request to the txnHistory array")
    it("Should adjust the account's availableBalance by the amount")
   */
  function submitTransaction(
    uint256 _accountID, 
    address payable _recipient, 
    uint256 _amount, 
    string calldata _tokenTicker
  ) external checkAccountPermissions(_accountID) returns (bool success, uint256 txID) {
    // Declare local variables
    txID = txnHistory.length;
    bytes32 tokenTickerBytes = tickerHash(_tokenTicker);

    // Check token exists
    require(tokenAddress[tokenTickerBytes] != address(0), "Token does not exist");
    // Check pending balance
    require (availableBalance[_accountID][tokenTickerBytes] >= _amount, "Insufficient balance");

    // Create new transaction request
    txnRequest memory pendingRequest =
    txnRequest({
              txID: txID,
              timestamp: block.timestamp,
              recipient: _recipient,
              accountID: _accountID,
              amount: _amount,
              ticker: tokenTickerBytes,
              approvalStatus: APPROVE.SUBMITTED
            });
    // Underflow should not be a problem, as availableBalance was already checked against _amount
    unchecked {
      // Push transaction request to transaction history
      txnHistory.push(pendingRequest);
      // Increment pendingTxns
      pendingTxns++;

      // Adjust account's pending balance
      // Note account's true balance is updated when tokens are deposited or transaction is approved
      availableBalance[_accountID][tokenTickerBytes] -= _amount;
    }

    // Emit events, return success bool
    emit TransactionSubmitted(txID, block.timestamp);
    emit TransactionDetails(txID, _accountID, _recipient, _amount);
    success = true;
  }

  /**
   * @notice Votes to confirms a transaction

    UNIT TESTS PART 1:
    it("Should revert if token was deleted after submission")
    it("Should revert if request does not exist")
    it("Should change Submitted status to Pending")
    it("Should update Admin's approval status for the request")
    it("Should not allow Admin to confirm twice")
    it("Should not confirm if multi-sig requirement is not reached")
    it("Should confirm when multi-sig requirement is reached")
    it("Should adjust trueBalance when confirmed")
    it("Should transfer ETH correctly")
    it("Should transfer tokens correctly")

    UNIT TESTS PART 2:
    it("Should throw when confirming an Approved transfer")
    it("Should throw when confirming a Cancelled transfer")
   */
  function confirmTransfer(uint256 _txID) external onlyAdmin returns (bool txnApproved) {
    // Declare local variables
    txnRequest memory approvedTxn = txnHistory[_txID];
    APPROVE status = approvedTxn.approvalStatus;
    
    // Check token was not deleted after submission
    require(tokenAddress[approvedTxn.ticker] != address(0), "Token deleted");
    // Check transaction exists
    require(_txID < txnHistory.length, "Request does not exist");
    // Check transaction hasn't been approved already
    require(status != APPROVE.APPROVED, "Request approved");
    // Check transaction hasn't been cancelled
    require(status != APPROVE.CANCELLED, "Request cancelled");
    // Check Admin has not already approved transaction
    require(!adminApproved[msg.sender][_txID], "Admin approved");

    // If txnRequest was Submitted, then set storage approvalStatus to Pending    
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

  /**
   * @notice Tallies up Admin approvals for transaction, processes transaction if multi-sig 
   * requirement is met
   * @dev Uses unchecked logic for tallying Admin approvals, but uses checked logic for adjusting
   * trueBalance. Further testing is needed to determine if trueBalance can ever underflow, and
   * if not then it should be unchecked as well to save gas.
   */
  function _txnApproval(uint256 _txID) private returns (bool) {
    // 0. Initialize local variables
    uint256 numApproved = 0;
    txnRequest memory transaction = txnHistory[_txID];

    // 1. Iterate through admins array and tally up approvals
     // Unchecked because loop counter and numApproved will not exceed uint256 type size
    unchecked {
      for (uint256 i = 0; i < admins.length; i++) {
        // Tertiary operator: If Admin approved then increment counter, if not then leave alone
        adminApproved[admins[i]][_txID] ?
          numApproved++ :
          numApproved;
      }      
    }

    // 2. If approvals did not meet requirement, then return from function with false flag
    if (numApproved < adminsRequired) {
      return false;
    }

    // 3. Otherwise, proceed with transfer

    //*** EFFECTS ***\\      
    // Update transaction's approval status to Approved
    txnHistory[_txID].approvalStatus = APPROVE.APPROVED;
    // Update account's true balance
    trueBalance[transaction.accountID][transaction.ticker] -= transaction.amount;
    // Decrement pendingTxns
    pendingTxns--;

    // Emit approval event
    emit TransactionApproved(_txID, block.timestamp);

    //*** INTERACTIONS ***\\
    // Logic for transferring ETH
    if(tokenAddress[transaction.ticker] == address(this)){
      // Transfer ETH to recipient, then return from function
      transaction.recipient.transfer(transaction.amount);
      return true;
    }
    // Logic for ERC20 transfer
    else if(
      IERC20(tokenAddress[transaction.ticker])
      .transfer(transaction.recipient, transaction.amount)
    ){
      return true;
    }

    // If function has not returned yet, then all conditionals failed, and therefore transfer failed,
    // revert with an error message
    revert("Transfer failed");
  }

  /**
   * @notice Cancels Pending transaction
    UNIT TESTS:
    it("Should revert for non-existent requests")
    it("Should revert for Approved requests")
    it("Should revert for Cancelled requests")
    it("Should update status to Cancelled")
    it("Should update account's availableBalance")
   */
  function cancelTransaction(uint256 _txID) external onlyAdmin returns(bool) {
    // Declare local variables
    txnRequest memory transaction = txnHistory[_txID];

    // Check transaction exists
    require(_txID < txnHistory.length, "Request doesn't exist");
    // Check transaction hasn't been approved already
    require(transaction.approvalStatus != APPROVE.APPROVED, "Request approved");
    // Check transaction hasn't been cancelled
    require(transaction.approvalStatus != APPROVE.CANCELLED, "Request cancelled");

    // Update transaction approval status to Cancelled
    txnHistory[_txID].approvalStatus = APPROVE.CANCELLED;
    // Update account's pending balance
    availableBalance[transaction.accountID][transaction.ticker] += transaction.amount;
    // Decrement pendingTxns
    pendingTxns--;

    // Emit cancellation alert
    emit TransactionCancelled(_txID, msg.sender, block.timestamp);
    return true;
  }

  /**
   * @notice Deposits ERC20 tokens into an account
   * @dev Permits non-Admins to deposit tokens into public accounts. This can
   * be used for donations and business applications that need a designated
   * account.
   *
   * @param _ticker ERC20 ticker symbol
   * @param _amount Amount to deposit
   * @param _accountID Treasury account to deposit token into

    UNIT TESTS:
    it("Should not work for ticker ETH")
    it("Should not work for tokens that weren't added")
    it("Should not work for zero amounts")
    it("Should revert for insufficient allowance")
    it("Should update account's trueBalance")
    it("Should update account's availableBalance")
   */
  function depositToken(
    string calldata _ticker, 
    uint256 _amount, 
    uint256 _accountID
  ) external checkAccountPermissions(_accountID) returns(bool) {
    // Declare local variables
    bytes32 tickerBytes = tickerHash(_ticker);
    address tokenAddr = tokenAddress[tickerBytes];

    //*** CHECKS ***\\
    // Check Admin is not depositing ETH
    require(tickerBytes != ETH, "Use depositETH");
    // Check token exists in this contract
    require(tokenAddr != address(0), "Add token first");
    // Check amount is not zero
    require(_amount != 0, "Amount zero");

    //*** EFFECTS ***\\
    // Update account's balances
    trueBalance[_accountID][tickerBytes] += _amount;
    availableBalance[_accountID][tickerBytes] += _amount;

    //*** INTERACTIONS ***\\
    // Call ERC20 contract's transferFrom function
    require(IERC20(tokenAddr).transferFrom(msg.sender, address(this), _amount), "Transfer failed");
    return true;
  }

  /**
   * @notice Deposits ETH amount
   * @dev Most accounts require Admin permissions to deposit, but some accounts that are made
   * "public" can be deposited into by non-Admins
    UNIT TESTS:
    it("Should revert if 0 ether is sent")
    it("Should update correct account's trueBalance")
    it("Should update correct account's availableBalance")
   */
  function depositETH(uint256 _accountID) external payable checkAccountPermissions(_accountID) returns(bool) {
    // Check amount is not zero
    require(msg.value != 0, "Amount zero");

    // Update account's balances
    trueBalance[_accountID][ETH] += msg.value;
    availableBalance[_accountID][ETH] += msg.value;

    emit ETHDeposited(_accountID, msg.value, block.timestamp);
    return true;
  }  

  /**
   * @notice Moves tokens from one account to another
   * @dev This is not a multi-sig operation, but should be permissioned to a role
   * @dev Multi-sig mechanism can be modified to allow internal transfers to require
   * multi-sig authorization, but will increase contract complexity substantially.

    UNIT TESTS:
    it("Should not transfer tokens from account with insufficient availableBalance")
    it("Should update both accounts' balances correctly")
   */
  function internalTransfer(
    string calldata _ticker, 
    uint256 _amount, 
    uint256 _accountIDFrom, 
    uint256 _accountIDTo
  ) external onlyAdmin returns(bool) {
    bytes32 ticker = tickerHash(_ticker);

    // Check that sending account has sufficient balances
    require(
      availableBalance[_accountIDFrom][ticker] >= _amount &&
      trueBalance[_accountIDFrom][ticker] >= _amount, // This may not be necessary
      "Insufficient balance"
    );

    // Update internal balances
    trueBalance[_accountIDFrom][ticker] -= _amount;
    availableBalance[_accountIDFrom][ticker] -= _amount;
    trueBalance[_accountIDTo][ticker] += _amount;
    availableBalance[_accountIDTo][ticker] += _amount;

    // Emit alert for internal transfer
    emit InternalTransfer(_ticker, _amount, _accountIDFrom, _accountIDTo, msg.sender, block.timestamp);
    return true;
  }

  /**
   * @notice Deposits ETH into main account 
    it("Should update trueBalance and availableBalance when ETH is deposited")
   */
  receive() external payable {
    // Update main account's balances
    trueBalance[mainAccountID][ETH] += msg.value;
    availableBalance[mainAccountID][ETH] += msg.value;    

    emit ETHDeposited(mainAccountID, msg.value, block.timestamp);
  }

  // Throws error message when invalid function is called with/without ETH
  fallback() external payable {
    revert("Invalid function");
  }

  /**
   * @notice Adds or modifies an ERC20 token
   * @dev Admins can use _tokenAddress = address(0) to delete a token, which will cause all pending
   * transfers of that token to cancel when confirmation is attempted.
   *
   * @param _ticker ERC20 ticker symbol, cannot be ETH
   * @param _tokenAddress ERC20 contract address, cannot be address(this)

    UNIT TESTS:
    it("Should revert for ETH ticker")
    it("Should assign tokenTicker mapping correctly if new")
    it("Should not change tokenTicker mapping if token exists")
    it("Should assign/reassign address correctly")
   */
  function modifyToken(string calldata _ticker, address _tokenAddress) external onlyAdmin returns (bool) {
    // Hash token's ticker symbol
    bytes32 tokenTickerBytes = keccak256(abi.encodePacked(_ticker));

    // Check caller is not overriding ETH assignments
    require(
      tickerHash(_ticker) != ETH &&
      tokenAddress[tokenTickerBytes] != address(this) &&
      _tokenAddress != address(this),
      "Cannot override ETH assignments"
    );

    // If token does not exist or was deleted, then fire ERC20Added event
    if(tokenAddress[tokenTickerBytes] == address(0)){
      // Emit ERC20Added alert
      emit ERC20Added(
        _ticker, 
        tokenTickerBytes, 
        _tokenAddress,
        msg.sender,
        block.timestamp
      );
    }
    // Otherwise, emit ERC20Modified event
    else {
      emit ERC20Modified(
        _ticker, 
        tokenTickerBytes, 
        tokenAddress[tokenTickerBytes], 
        _tokenAddress, 
        msg.sender,
        block.timestamp
      );
    }

    // Map ticker symbol hash to its contract address
    tokenAddress[tokenTickerBytes] = _tokenAddress;

    return true;
  }

  /**
   * @notice Sets an account's permissions, either Public or Admin
   * @dev All accounts are Admin-restricted by default
   * @dev Upgrade to OpenZeppelin's AccessControl system for greater flexibility
   */
  function setAccountPermission(uint256 _accountID, bool _isPublic) external onlyAdmin returns (bool) {
    isPublic[_accountID] = _isPublic;

    return true;
  }

  /**
   * @notice Returns pending transaction IDs, sorted from most recent to oldest
   * @dev While this is a view function, it is gas-optimized for smart contract use.
   * An alternative design can be made which does not use a state variable to track
   * number of pending transactions, but it adds a second loop to this function and
   * requires iterating through entire txnHistory array, which may be rejected by a
   * node even if it is view-only, should txnHistory contain hundreds/thousands of 
   * elements.
   * @dev Front end: Feed this function's output into the txnHistory array's public
   * getter function to produce an array of all pending transaction details.
   */
  function getPendingIDs() public view returns (uint256[] memory pendingTxnIDs) {
    // Check for pending requests
    require(pendingTxns > 0, "No pending requests");

    // Initialize variables
    uint256 j = 0; // Index counter for pendingTxnIDs
    uint i = txnHistory.length; // Starting point for loop counter
    // Define size of pendingTxnIDs as pendingTxns
    pendingTxnIDs = new uint256[](pendingTxns);

    // Unchecked because i underflow is prevented by loop conditions
    unchecked {
      // Populate pendingTxnIDs
      while(j < pendingTxns && i > 0){
        // Store transaction in local memory and decrement i
        txnRequest memory transaction = txnHistory[i - 1];
        i--;

        // If transaction was Approved or Cancelled, then skip to next transaction
        if (
          transaction.approvalStatus == APPROVE.APPROVED ||
          transaction.approvalStatus == APPROVE.CANCELLED
          ) {
            continue;
        }

        // Add transaction ID to pendingTxnIDs and increment j
        pendingTxnIDs[j] = transaction.txID;
        j++;
      }      
    }
    
    // Return completed array of transaction IDs
    return pendingTxnIDs;
  }



}
