/** 
 * @title Treasury V2
 * @author Phoenix "CryptoPhoenix" Angell
 * @notice A multi-signature treasury management contract for both ERC20 and ETH holdings. Manages multiple accounts, each assigned a uint256 identifier, and each can be permissioned for Admins or for Public use. Anyone can deposit tokens into or request withdrawals from a Public account, but Admin-restricted accounts can only be interacted with by Admins. All accounts must undergo multi-signature voting from Admins to process a withdrawal from, even Public. This allows the treasury to accept donations or take payment while keeping individual accounts separated for budget management purposes.
 * @dev The multi-sig mechanism in Treasury V2 is handled by a parent contract, which is a general-purpose multi-sig mechanism. See GeneralMultiSigV1.sol. 
 * @dev Treasury V3's multi-sig is handled by an external version of GeneralMultiSigV2.sol, and is used to demonstrate how an external multi-sig system would work.
 */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./GeneralMultiSigV1.sol";
import "./../OpenZeppelinDependencies/IERC20.sol";

contract TreasuryV2 is GeneralMultiSigV1 {
  
  /**
   * @notice Carries all on-chain data for account withdrawal requests
   *
   * @param requestID ID hash of withdrawal request
   * @param timestamp Block's timestamp when transaction request was submitted
   * @param recipient Recipient's address
   * @param acountID Uint256 ID of sending account
   * @param amount Amount of ERC20 tokens / ETH to send
   * @param ticker ERC20 token / ETH ticker's keccak256 hash
   */
  struct TxnRequest {
    uint256 timestamp;
    uint256 accountID;
    uint256 amount;
    bytes32 requestID;
    bytes32 ticker;
    address payable recipient;
  }

  // Used for minor functions that require multi-sig
  struct OtherRequest {
    bytes32 requestID;
    bytes32 inputsHash;
    uint256 timestamp;
  }

  // Maps account IDs to internal balance
   // Updated when tokens/ETH are deposited or withdrawn
   // Account ID => ticker hash => internal balance
  mapping(uint256 => mapping(bytes32 => uint256)) public trueBalance;
  // Maps account IDs to their pending balances
   // Updated when transactions are submitted or cancelled
   // Used to prevent over-spending before multi-sig vote can finish
   // Account ID => ticker hash => reported balance
  mapping(uint256 => mapping(bytes32 => uint256)) public pendingBalance;
  // Maps account IDs to public use permissions
   // Allows non-Admins to interact with / deposit into an account
   // Account ID => public permissions
  mapping(uint256 => bool) public isPublic;

  // Maps a token's keccak256 ticker to its contract address
  mapping(bytes32 => address) public tokenAddress;
  
  // History of all withdrawal requests:
  TxnRequest[] public txnHistory;
  // History of all other requests:
  OtherRequest[] public otherReqHistory;

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

  // Fires when any other multi-sig request is submitted
  event OtherRequestSubmitted(bytes32 indexed requestID, uint256 indexed otherID, uint256 timestamp);

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
  ) GeneralMultiSigV1(_admins, _numerator, _denominator) {
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
    it("Should adjust the account's pendingBalance by the amount")
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
    bytes32 requestID; // Defined after submitting for multi-sig

    // Check token exists
    require(tokenAddress[tokenTickerBytes] != address(0), "Token does not exist");
    // Check pending balance
    require (pendingBalance[_accountID][tokenTickerBytes] >= _amount, "Insufficient balance");

    // Hash inputs and submit multi-sig request, then store returned requestID
    requestID = _submitRequest(keccak256(abi.encodePacked(_accountID, _recipient, _amount, _tokenTicker)), txID);

    // Create new transaction request
    TxnRequest memory pendingRequest =
    TxnRequest({
              requestID: requestID,
              timestamp: block.timestamp,
              recipient: _recipient,
              accountID: _accountID,
              amount: _amount,
              ticker: tokenTickerBytes
            });

    // Underflow should not be a problem, as pendingBalance was already checked against _amount
    unchecked {
      // Push transaction request to transaction history
      txnHistory.push(pendingRequest);
      // Increment pendingTxns
      pendingTxns++;

      // Adjust account's pending balance
      // Note account's true balance is updated when tokens are deposited or transaction is approved
      pendingBalance[_accountID][tokenTickerBytes] -= _amount;
    }

    success = true;
  }

  /**
   * @notice Votes to confirms a transaction

    UNIT TESTS PART 1:
    it("Should revert if token was deleted after submission")
    it("Should revert if request does not exist")
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
  function confirmTransfer(uint256 _txID) external onlyAdmin returns (bool) {
    // Declare local variables
    TxnRequest memory approvedTxn = txnHistory[_txID];
    
    // Check token was not deleted after submission
    require(tokenAddress[approvedTxn.ticker] != address(0), "Token deleted");
    // Check transaction exists
    require(_txID < txnHistory.length, "Transaction does not exist");
    // Sanity check on account balance
    require(
      pendingBalance[approvedTxn.accountID][approvedTxn.ticker] >= approvedTxn.amount, 
      "Insufficient funds"
    );
    
    // Emit event for Admin's approval if they haven't voted yet
    if(!adminApproved[msg.sender][approvedTxn.requestID]){
      emit AdminApproved(_txID, msg.sender, block.timestamp);
    }
    
    // Run multi-sig check algorithm
    if(_confirmRequest(approvedTxn.requestID)){
      // If successful, then process transaction
      _processTxn(_txID);

      // Emit approval event and return true
      emit TransactionApproved(_txID, block.timestamp);
      return true;
    } 
    // If multi-sig fails, then return false
    else return false;
  }

  // Processes a transaction that passed multi-sig
  function _processTxn(uint256 _txID) private {
    // Store local variables
    TxnRequest memory transaction = txnHistory[_txID];

    //*** EFFECTS ***\\ 
    // Update account's true balance
    trueBalance[transaction.accountID][transaction.ticker] -= transaction.amount;
    // Decrement pendingTxns
    pendingTxns--;

    //*** INTERACTIONS ***\\
    // Logic for transferring ETH
    if(tokenAddress[transaction.ticker] == address(this)){
      // Transfer ETH to recipient, then return from function
      transaction.recipient.transfer(transaction.amount);
      return;
    }
    // Logic for ERC20 transfer, return from function if successful
    else if(
      IERC20(tokenAddress[transaction.ticker])
      .transfer(transaction.recipient, transaction.amount)
    ){
      return;
    }

    // If function has not returned yet, then all conditionals failed, and therefore transfer failed,
    // revert with an error message
    revert("Transfer failed");
  }

  // Submits a new Other Request for this contract, and submits a new multi-sig Request
  function _submitOtherRequest(bytes32 _inputHash) private returns(bool votePassed, bytes32 requestID, uint256 otherID) {
      // Store request's otherID
      otherID = otherReqHistory.length;
      // Submit multi-sig request and store returned requestID
      requestID = _submitRequest(_inputHash, otherID);

      // Create and store new OtherRequest struct
      OtherRequest memory newRequest = OtherRequest({
        requestID: requestID,
        inputsHash: _inputHash,
        timestamp: block.timestamp
      });
      otherReqHistory.push(newRequest);

      // Emit event, and return with new requestID and otherID
      emit OtherRequestSubmitted(requestID, otherID, block.timestamp);
      return (votePassed, requestID, otherID);
  }

  /**
   * @notice Cancels Pending transaction, does not require multi-sig

    UNIT TESTS:
    it("Should revert for non-existent requests")
    it("Should revert for Approved requests")
    it("Should revert for Cancelled requests")
    it("Should update status to Cancelled")
    it("Should update account's pendingBalance")
   */
  function cancelTransaction(uint256 _txID) external onlyAdmin returns(bool) {
    // Declare local variables
    TxnRequest memory transaction = txnHistory[_txID];

    // Check transaction exists
    require(_txID < txnHistory.length, "Transaction doesn't exist");

    // Cancel multi-sig vote request
    _cancelRequest(transaction.requestID);

    // Update account's pending balance
    pendingBalance[transaction.accountID][transaction.ticker] += transaction.amount;
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
    it("Should update account's pendingBalance")
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
    pendingBalance[_accountID][tickerBytes] += _amount;

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
    it("Should update correct account's pendingBalance")
   */
  function depositETH(uint256 _accountID) external payable checkAccountPermissions(_accountID) returns(bool) {
    // Check amount is not zero
    require(msg.value != 0, "Amount zero");

    // Update account's balances
    trueBalance[_accountID][ETH] += msg.value;
    pendingBalance[_accountID][ETH] += msg.value;

    emit ETHDeposited(_accountID, msg.value, block.timestamp);
    return true;
  }  

  /**
   * @notice Moves tokens from one account to another
   * @dev This is not a multi-sig operation, but should be permissioned to a role
   * @dev Multi-sig mechanism can be modified to allow internal transfers to require
   * multi-sig authorization, but will increase contract complexity substantially.

    UNIT TESTS:
    it("Should not transfer tokens from account with insufficient pendingBalance")
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
      pendingBalance[_accountIDFrom][ticker] >= _amount &&
      trueBalance[_accountIDFrom][ticker] >= _amount, // This may not be necessary
      "Insufficient balance"
    );

    // Update internal balances
    trueBalance[_accountIDFrom][ticker] -= _amount;
    pendingBalance[_accountIDFrom][ticker] -= _amount;
    trueBalance[_accountIDTo][ticker] += _amount;
    pendingBalance[_accountIDTo][ticker] += _amount;

    // Emit alert for internal transfer
    emit InternalTransfer(_ticker, _amount, _accountIDFrom, _accountIDTo, msg.sender, block.timestamp);
    return true;
  }

  /**
   * @notice Deposits ETH into main account 
    it("Should update trueBalance and pendingBalance when ETH is deposited")
   */
  receive() external payable {
    // Update main account's balances
    trueBalance[mainAccountID][ETH] += msg.value;
    pendingBalance[mainAccountID][ETH] += msg.value;    

    emit ETHDeposited(mainAccountID, msg.value, block.timestamp);
  }

  // Throws error message when invalid function is called with/without ETH
  fallback() external payable {
    revert("Invalid function");
  }

  /**
   * @notice Adds or modifies an ERC20 token, requires multi-sig approval
   * @dev When this function is called with _otherID = 0, a new multi-sig request will be
   * submitted using the function's inputs, and a new requestID and otherID will be returned.
   * To confirm this request, Admins must provide the same inputs and the otherID that was
   * returned from submission. When enough signatures are gathered, the function will return
   * votePassed = true and will fire appropriate events.
   *
   * @param _ticker ERC20 ticker symbol, cannot be ETH
   * @param _tokenAddress ERC20 contract address, cannot be address(this)
   * @param _otherID Other request ID to confirm, _otherID = 0 will submit new request
   *
   * @return votePassed Bool flag indicating if function call passed multi-sig vote
   * @return requestID Multi-sig ID for this request which tracks approval status
   * @return otherID Index value of otherReqHistory array, stores requestID
   *
   * Fires ERC20Added event when a new ERC20 token was added
   * Fires ERC20Modified event when an existing ERC20 token's address was updated

    UNIT TESTS:
    it("Should revert for ETH ticker")
    it("Should assign/reassign address correctly")
   */
  function modifyToken(string calldata _ticker, address _tokenAddress, uint256 _otherID) external onlyAdmin returns (bool votePassed, bytes32 requestID, uint256 otherID) {
    // Store local variables
    OtherRequest memory request = otherReqHistory[_otherID];
    requestID = request.requestID; // Only changes if _otherID = 0
    otherID = _otherID; // Only changes if _otherID = 0
    votePassed = false; // Vote does not pass until stated otherwise
    // Hash the token's ticker symbol
    bytes32 tokenTickerBytes = keccak256(abi.encodePacked(_ticker));
    // Hash the function's inputs
    bytes32 inputHash = keccak256(abi.encodePacked(_ticker, _tokenAddress));

    // Check caller is not overriding ETH assignments
    require(
      tickerHash(_ticker) != ETH &&
      tokenAddress[tokenTickerBytes] != address(this) &&
      _tokenAddress != address(this),
      "Cannot override ETH assignments"
    );

    // If Admin submitted new request, then submit new request and return
    if(_otherID == 0){
      (votePassed, request.requestID, otherID) = _submitOtherRequest(inputHash);
      return (votePassed, request.requestID, otherID);
    }

    // Otherwise, check that Admin submitted correct inputs before proceeding
    else{
      require(request.inputsHash == inputHash, "Wrong arguments given");
    }

    // Run multi-sig check, fire event and update token address if vote passes
    if(_confirmRequest(requestID)){
      votePassed = true;
      // If token has no address, then fire ERC20Added event
      if(tokenAddress[tokenTickerBytes] == address(0)){
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

      // Update token's contract address
      tokenAddress[tokenTickerBytes] = _tokenAddress;

      return (votePassed, request.requestID, _otherID);
    }

    // If function has not returned yet, then return values do not change
    return (votePassed, request.requestID, _otherID);
  }

  /**
   * @notice Sets an account's permissions, either Public or Admin
   * @dev All accounts are Admin-restricted by default
   * @dev Upgrade to OpenZeppelin's AccessControl system for greater flexibility
   */
  function setAccountPermission(uint256 _accountID, bool _isPublic, uint256 _otherID) external onlyAdmin returns (bool votePassed, bytes32 requestID, uint256 otherID) {
    // Set default multi-sig return values
    votePassed = false;
    requestID = otherReqHistory[_otherID].requestID;
    otherID = _otherID;
    // Hash function inputs
    bytes32 inputHash = keccak256(abi.encodePacked(_accountID, _isPublic));

    // If _otherID == 0, then submit a new request and return new multi-sig values
    if(_otherID == 0){
      return _submitOtherRequest(inputHash);
    }

    // Otherwise, proceed with multi-sig vote
    if(_confirmRequest(requestID)){
      // If the vote passed, then update account's Public/Admin permissions and return
      isPublic[_accountID] = _isPublic;
      return (votePassed, requestID, otherID);
    }
  }

  /**
   * @notice Returns pending transaction IDs, sorted from most recent to oldest
   * @dev While this is a view function, it is gas-optimized for smart contract use.
   * An alternative design can be made which does not use a state variable to track
   * number of pending transactions, but it adds a second loop to this function and
   * requires iterating through entire txnHistory array, which may be rejected by a
   * node even if it is view-only, should txnHistory contain hundreds/thousands of 
   * elements.
   * @dev Front end: Feed this function's outputs into the txnHistory array's public
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

    // Unchecked because i underflow is prevented by loop condition
    unchecked {
      // Populate pendingTxnIDs
      while(j < pendingTxns && i > 0){
        // Store transaction and request approval status
        TxnRequest memory transaction = txnHistory[i - 1];
        APPROVE approvalStatus = requestIDMap[transaction.requestID].approvalStatus;

        // If transaction was Approved or Cancelled, then skip to next transaction
        if (
          approvalStatus == APPROVE.APPROVED ||
          approvalStatus == APPROVE.CANCELLED
          ) {
            i--;
            continue;
        }

        // Add transaction's index ID to pendingTxnIDs, increment j, and decrement i
        pendingTxnIDs[j] = i;
        j++;
        i--;
      }      
    }
    
    // Return completed array of transaction IDs
    return pendingTxnIDs;
  }

}
