/** 
 * @title Treasury V3
 * @author Phoenix "CryptoPhoenix" Angell
 * @notice A multi-signature treasury management contract for both ERC20 and ETH holdings. Manages multiple accounts, each assigned a uint256 identifier, and each can be permissioned for various roles. Anyone can deposit tokens into or request withdrawals from a Public account, but role-restricted accounts can only be interacted with by users who hold the appropriate roles. All accounts must undergo multi-signature voting from role-holders to process a withdrawal request, even Public accounts. This allows the treasury to accept donations or take payments while keeping individual accounts separated for budget management purposes (i.e. development, marketing, treasury).
 * @dev Treasury V3's multi-sig is handled by GeneralMultiSigV3.sol, an external universal multi-sig contract. This contract can be deployed for general, non-permissioned public use, or it can be forked and deployed for a mapped list of addresses for an ecosystem of project-owned smart contracts.
 * @dev This contract uses a modified variant of OpenZeppelin's AccessControl, which has been overidden to assign roles to accounts, and check if users have the necessary roles to submit/confirm transactions for those accounts.
 *
 */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./GeneralMultiSigV3.sol";
import "./IGenMulSigV3.sol";
import "./../WalletAdminsV1-1.sol";
import "./../OpenZeppelinDependencies/IERC20.sol";
import "./AccessControl.sol";
import "./ITreasuryV3.sol";

contract TreasuryV3 is ITreasuryV3, AccessControl {
  
  //*** STRUCTS ***\\
  /**
   * @notice Stores on-chain data for account withdrawal requests
   *
   * @param recipient Recipient's address
   * @param accountID Uint256 ID of sending account
   * @param amount Amount of ERC20 tokens / ETH to send
   * @param ticker ERC20 token / ETH ticker's keccak256 hash
   */
  struct TxnData {
    uint256 accountID;
    uint256 amount;
    bytes32 ticker;
    address payable recipient;
  }

  /**
   * @notice Stores on-chain data for a multi-sig request
   *
   * @param txnData Stores TxnData data, if applicable for request
   * @param funcName Name of function represented by the RequestData
   * @param requestID ID hash of withdrawal request
   * @param timestamp Block's timestamp when transaction request was submitted
   * @param role Role assigned to the account ID
   * @param inputsHash Hashed inputs for the function represented by this
   */
  struct RequestData {
    TxnData txnData;
    bytes32 funcName;
    uint256 timestamp;
    bytes32 requestID;
    bytes32 inputsHash;
    bytes32 role;
    bool requestActive;
  }

  /**
   * @param accountData Role required to interact with account
   * @param grossBalance Account's total token/ETH balance, updated upon confirmation 
   * @param netBalance Account's token/ETH balance, updated upon submission
   */
  struct AccountData {
    bytes32 role;
    mapping(bytes32 => uint256) grossBalance; // Token/ETH gross balance
    mapping(bytes32 => uint256) netBalance; // Token/ETH net balance
  }

  //*** MAPPINGS ***\\
  // Maps account IDs to their data structs
  mapping(uint256 => AccountData) public accountData;
  // Maps a token's hashed ticker to its contract address
  mapping(bytes32 => address) private tokenAddressMap;

  //*** STATE VARIABLES ***\\  
  // Ticker hash for ether
  bytes32 public immutable ETH;
  // Account that receives ether through receive function
  uint256 public defaultAccountID;
  // Tracks total number of pending transactions
  uint256 public pendingTxns;
  // External multi-sig contract
  IGeneralMultiSigV3 public immutable iMultiSig;

  // History of all multi-sig requests:
  RequestData[] public requestHistory;

  /**
   * @param _multiSigContract Address of GeneralMultiSigV3 contract
   * @param _defaultAccount Default account tokens/ETH are deposited into via fallback/receive functions
   * @param _tickers Array of ERC20 ticker strings
   * @param _tokenContracts Array of ERC20 token contract addresses
   * @param _admins Array of all admins and their roles at deployment, admins may have multiple roles
   *        @dev _admins[i][] will be assigned _roles[i]
   * @param _accountIDs Array of all accounts at deployment, only one role per account
   *        @dev _accountIDs[i] will be assigned _roles[i]
   * @param _roles Array of all roles at deployment
   *        @dev One of these roles must be "ADMIN"
   *        @dev One of these roles must be "PUBLICADMIN"
   *        @dev No roles are needed for "PUBLIC"
   * @param _ratios Multi-sig ratios for each role
   *        @dev _ratios[i][0] = numerator
   *        @dev _ratios[i][1] = denominator
   */
  constructor(
    address _multiSigContract,
    uint256 _defaultAccount,
    bytes32[] memory _tickers,
    address[] memory _tokenContracts,
    address[][] memory _admins, 
    uint256[] memory _accountIDs,
    string[] memory _roles,
    uint256[][] memory _ratios
  ) AccessControl(_admins, _roles) {
    require(_tickers.length == _tokenContracts.length, "Array lengths mismatched");
    super;
    // Assign multi-sig contract's address
    iMultiSig = IGeneralMultiSigV3(_multiSigContract);

    // Add ETH's ticker to contract, using address(this) as its tokenAddress
    bytes32 ETHConstructor = keccak256(abi.encodePacked("ETH"));
    ETH = ETHConstructor;
    tokenAddressMap[ETHConstructor] = address(this);
    defaultAccountID = _defaultAccount; // Assign default ETH receiving account

    // Set default account role
    bytes32 PUBLICConstructor = keccak256(abi.encodePacked("PUBLIC"));
    accountData[_defaultAccount].role = PUBLICConstructor; // Default account has Public permissionss

    // Setup all accounts, admin roles, and multi-sig ratios
    for(uint256 i = 0; i < _roles.length; i++){
      // Hash the role's name
      bytes32 role = keccak256(abi.encodePacked(_roles[i]));
      
      // Assign role to accountID
      accountData[_accountIDs[i]].role = role;
      
      // Store role's multi-sig ratio
      roleData[role].ratios[0] = _ratios[i][0]; // Numerator
      roleData[role].ratios[1] = _ratios[i][1]; // Denominator

    }

    // Upload ERC20 tokens into contract
     // Unchecked because counter variable will never exceed length of _tickers array
    unchecked {
      for(uint256 i = 0; i < _tickers.length; i++){
        // Hash token's ticker string
        bytes32 ticker = keccak256(abi.encodePacked(_tickers[i]));        
        // Map ticker symbol hash to its contract address
        tokenAddressMap[ticker] = _tokenContracts[i];

        // Emit ERC20Added alert
        emit ERC20Added({
          requestID: 0,
          txnID: 0,
          ticker: _tickers[i], 
          tokenAddress: _tokenContracts[i], 
          adminCaller: msg.sender, 
          timestamp: block.timestamp
        });
      }
    }

  }

  // Checks that transaction exists
  modifier txnExists(uint256 _txnID) {
    // Check transaction exists
    require(_txnID < requestHistory.length, "Transaction doesn't exist");
    _;
  }

  // Checks that an ERC20 token has been added to the contract
  modifier tokenExists(bytes32 _tokenHash) {
    // Check token exists
    require(tokenAddressMap[_tokenHash] != address(0), "Invalid token");
    _;
  }

  /**
   * @notice Returns the number of votes needed to pass multi-sig threshold for a role
   * @dev Needed by GeneralMultiSigV3.sol
   */
  function votesRequired(bytes32 _role) public view returns (uint256){
    uint256 numerator = roleData[_role].ratios[0];
    uint256 denominator = roleData[_role].ratios[1];

    return (roleData[_role].roleCount * numerator) / denominator;
  }

  function hasRole(bytes32 role) public view returns (bool) {
      return roleData[role].members[msg.sender];
  }

  /**
   * @notice Helper function for ticker symbol hashing
   * //REMOVE
   */
  function tickerHash(string calldata _ticker) public pure returns (bytes32) {
    return keccak256(abi.encodePacked(_ticker));
  }

  /**
   * @notice Submits a new transaction request
   *
   * @param _accountID ID of account to withdraw from
   * @param _recipient Transaction recipient
   * @param _amount Amount of tokens/ETH being sent
   * @param _tokenTicker Ticker symbol of token/ETH being transferred
   *
   * @return success Success bool
   * @return txnID Local transaction ID
   * @return requestID Multi-sig request ID

    UNIT TESTS:
    it("Should not submit a transaction greater than its net balance")
    it("Should add the request to the requestHistory array")
    it("Should adjust the account's netBalance by the amount")
   */
  function submitTransaction(
    uint256 _accountID, 
    address payable _recipient, 
    uint256 _amount, 
    bytes32 _tokenTicker
  ) external returns (bool success, uint256 txnID, bytes32 requestID) {
    //*** INITIALIZE VARIABLES ***\\
    // Define and retrieve multi-sig input data
    bytes32 inputsHash = keccak256(abi.encodePacked(_accountID, _recipient, _amount, _tokenTicker));
    bytes32 funcName = keccak256(abi.encodePacked("submitTransaction"));
    bytes32 role = accountData[_accountID].role;

    //*** CHECKS ***\\
    // Check caller's role permissions for this account
    _checkRole(role);
    // Check account's net balance
    require (accountData[_accountID].netBalance[_tokenTicker] >= _amount, "Insufficient balance");

    //*** EFFECTS ***\\
    // Create new transaction request, push to history array, and adjust account's net balance
      // Create a new TxnData struct
      TxnData memory newRequest = _createNewTransaction(_accountID, _amount, _tokenTicker, _recipient);
      // Create a new RequestData struct, push to history array
      requestHistory.push(_createNewRequest(funcName, inputsHash, role, newRequest));
      // Increment pendingTxns
      pendingTxns++;
      // Adjust account's on-chain net balance
      accountData[_accountID].netBalance[_tokenTicker] -= _amount;


    //*** INTERACTIONS ***\\
    // Submit multi-sig request to external contract
    (requestID, txnID) = _submitRequest(funcName, inputsHash, role, newRequest);

    // Emit submission event and set success flag to true
    emit TransactionSubmitted(txnID, _accountID, requestID, msg.sender, _recipient, _amount, block.timestamp);
    assert(
      accountData[_accountID].netBalance[_tokenTicker] <= 
      accountData[_accountID].grossBalance[_tokenTicker]
    ); //REMOVE
    success = true;
  }

  /**
   * @notice Confirms a transaction, processes transaction if multi-sig vote approves

    UNIT TESTS PART 1:
    it("Should revert if token was deleted after submission")
    it("Should revert if request does not exist")
    it("Should update Admin's approval status for the request")
    it("Should not allow Admin to confirm twice")
    it("Should not confirm if multi-sig requirement is not reached")
    it("Should confirm when multi-sig requirement is reached")
    it("Should adjust grossBalance when confirmed")
    it("Should transfer ETH correctly")
    it("Should transfer tokens correctly")

    UNIT TESTS PART 2:
    it("Should throw when confirming an Approved transfer")
    it("Should throw when confirming a Cancelled transfer")
   */
  function confirmTransfer(uint256 _txnID) external txnExists(_txnID) returns (bool) {
    //*** INITIALIZE ***\\
    RequestData memory request = requestHistory[_txnID];
    TxnData memory transaction = request.txnData;
    
    //*** CHECKS ***\\
    // Check caller's role permissions for the transaction's account ID
    _checkRole(request.role);
    // Check token was not deleted after request submission
    require(tokenAddressMap[transaction.ticker] != address(0), "Token deleted");
    // Sanity check on account balance, may not be necessary
    require(
      accountData[transaction.accountID].netBalance[transaction.ticker] >= transaction.amount, 
      "Insufficient funds"
    );
    
    //*** EFFECTS ***\\
    // No effects to update at this point until multi-sig has confirmed approval

    //*** INTERACTIONS ***\\
    // Run multi-sig confirmation
    if(iMultiSig.confirmRequest(
        request.requestID, 
        msg.sender, 
        request.role
      )){
      // If request was approved, then process transaction
      _processTxn(_txnID);

      // Emit approval event and return true
      emit TransactionApproved(_txnID, block.timestamp);
      return true;
    } 
    // If multi-sig did not confirm the request, then return false
    else return false;
  }

  // Processes a transaction that passed multi-sig confirmation
  function _processTxn(uint256 _txnID) private {
    //*** INITIALIZE ***\\
    TxnData memory transaction = requestHistory[_txnID].txnData;

    //*** EFFECTS ***\\ 
    // Update account's gross balance
    accountData[transaction.accountID].grossBalance[transaction.ticker] -= transaction.amount;
    // Decrement pendingTxns
    pendingTxns--;

    assert(
      accountData[transaction.accountID].grossBalance[transaction.ticker] <= 
      accountData[transaction.accountID].netBalance[transaction.ticker]
    ); //REMOVE

    //*** INTERACTIONS ***\\
    // Logic for transferring ETH
    if(transaction.ticker == ETH){
      // Transfer ETH to recipient, then return from function
      transaction.recipient.transfer(transaction.amount);
      return;
    }
    // Logic for ERC20 transfer, return from function if successful
    else if(
      IERC20(tokenAddressMap[transaction.ticker])
      .transfer(
        transaction.recipient, 
        transaction.amount
      )
    ){
      return;
    }

    // If function has not returned yet, then all conditionals failed, revert with error message
    revert("Transfer failed");
  }

  /**
   * @notice Submits and stores a new multi-sig Request
   *
   * @param _funcName String name of function
   * @param _inputHash Hashed inputs of function
   * @param _role User role required for multi-sig authorization
   * @param _txnData Transaction data, if applicable
   *
   * @return requestID Multi-signature request identifier
   * @return txnID Request history index number
   */
  function _submitRequest(
    bytes32 _funcName, 
    bytes32 _inputHash, 
    bytes32 _role, 
    TxnData memory _txnData
  ) private returns(bytes32 requestID, uint256 txnID) {
    // Retrieve request's transaction ID
    txnID = requestHistory.length;
    // Create and push new request to the history array
    RequestData memory newRequest = _createNewRequest(_funcName, _inputHash, _role, _txnData); 
    // Submit external multi-sig request and record returned requestID
    newRequest.requestID = iMultiSig.submitRequest(_inputHash, _role);
    // Store final request data struct into request history array
    requestHistory.push(newRequest);

    // Emit event, and return with new requestID and txnID
    emit RequestSubmitted({
      requestID: requestID, 
      txnID: txnID, 
      role: _role,
      funcName: _funcName, 
      inputsHash: _inputHash,
      timestamp: block.timestamp
    });
    return (requestID, txnID);
  }

  /**
   * @notice Creates and returns a new TxnData struct
   *
   * @param _accountID Account identifier to transfer from
   * @param _amount Amount of tokens/ETH to be transferred
   * @param _ticker Hash of token/ETH ticker symbol
   * @param _recipient Receiving address
   *
   * @return txnData Completed TxnData struct
   */
  function _createNewTransaction(
    uint256 _accountID, 
    uint256 _amount, 
    bytes32 _ticker, 
    address payable _recipient
  ) private pure returns (TxnData memory txnData) {
    txnData = TxnData({
      accountID: _accountID,
      amount: _amount,
      ticker: _ticker,
      recipient: _recipient 
    });
  }

  /**
   * @notice Creates a new RequestData struct, and submits request to multi-sig contract 
   *
   * @param _funcName String name of function
   * @param _inputHash Hashed inputs of function
   * @param _role User role required for multi-sig authorization
   * @param _txnData Transaction data, if applicable
   *
   * @return newRequest Almost-completed RequestData struct, only requestID is needed
   */
  function _createNewRequest(
    bytes32 _funcName, 
    bytes32 _inputHash, 
    bytes32 _role, 
    TxnData memory _txnData
  ) private view returns(RequestData memory newRequest) {
    // Create new RequestData struct
    newRequest = RequestData({
      txnData: _txnData,
      requestID: 0, // Temporary value
      inputsHash: _inputHash,
      timestamp: block.timestamp,
      role: _role,
      requestActive: true,
      funcName: _funcName
    });
  }

  // Creates an empty TxnData struct, used for administrative functions
  function _createEmptyTxn() private returns (TxnData memory emptyData) {
    emptyData = TxnData({
      accountID: 0,
      amount: 0,
      ticker: 0,
      recipient: payable(address(this))
    });    
  }

  /**
   * @notice Cancels Pending transaction, must be called by roleholder of account,
   * and Public account cancellations must be called by a Public Admin.

    UNIT TESTS:
    it("Should revert for non-existent requests")
    it("Should revert for Approved requests")
    it("Should revert for Cancelled requests")
    it("Should update status to Cancelled")
    it("Should update account's netBalance")
   */
  function cancelTransaction(uint256 _txnID) external txnExists(_txnID) returns(bool) {
    // Declare local variables
    RequestData memory request = requestHistory[_txnID];
    TxnData memory transaction = request.txnData;

    //*** CHECKS ***\\
    // Check caller's role permissions for the transaction's account ID
    _checkRole(request.role);
    // Require caller hold Public Admin role for Public accounts
    if(request.role == PUBLIC){
      require(hasRole(PUBLICADMIN), "Only Admin");
    }

    //*** EFFECTS ***\\
    // Update account's net balance
    accountData[transaction.accountID].netBalance[transaction.ticker] += transaction.amount;
    // Decrement pendingTxns
    pendingTxns--;

    //*** INTERACTIONS ***\\
    // Cancel multi-sig vote request
    iMultiSig.cancelRequest(request.requestID);

    // Emit cancellation alert
    emit TransactionCancelled({
      txnID: _txnID,
      caller: msg.sender, 
      timestamp: block.timestamp 
    });
    assert(
      accountData[transaction.accountID].netBalance[transaction.ticker] <= 
      accountData[transaction.accountID].grossBalance[transaction.ticker]
    ); //REMOVE
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
    it("Should update account's grossBalance")
    it("Should update account's netBalance")
   */
  function depositToken(
    bytes32 _ticker, 
    uint256 _amount, 
    uint256 _accountID
  ) external returns(bool) {
    // Declare local variables
    address tokenAddr = tokenAddressMap[_ticker];
    bytes32 role = accountData[_accountID].role;

    //*** CHECKS ***\\
    // Check caller's account role
    _checkRole(role);
    // Check Admin is not depositing ETH
    require(_ticker != ETH, "Use depositETH");
    // Check token exists in this contract
    require(tokenAddr != address(0), "Add token first");
    // Check amount is not zero
    require(_amount != 0, "Amount zero");

    //*** EFFECTS ***\\
    // Update account's balances
    accountData[_accountID].grossBalance[_ticker] += _amount;
    accountData[_accountID].netBalance[_ticker] += _amount;

    //*** INTERACTIONS ***\\
    // Call ERC20 contract's transferFrom function
    require(IERC20(tokenAddr).transferFrom(msg.sender, address(this), _amount), "Transfer failed");

    // Emit event for token deposit
    emit TokenDeposited({
      ticker: _ticker, 
      tokenAddress: tokenAddr,
      accountID: _accountID, 
      amount: _amount, 
      timestamp: block.timestamp
    });
    return true;
  }

  /**
   * @notice Deposits ETH amount
   * @dev Most accounts require Admin permissions to deposit, but some accounts that are made
   * "public" can be deposited into by non-Admins
    UNIT TESTS:
    it("Should revert if 0 ether is sent")
    it("Should update correct account's grossBalance")
    it("Should update correct account's netBalance")
   */
  function depositETH(uint256 _accountID) external payable returns(bool) {
    bytes32 role = accountData[_accountID].role;

    // Check caller's account role
    _checkRole(role);
    // Check amount is not zero
    require(msg.value != 0, "Amount zero");

    // Update account's balances
    unchecked {
      accountData[_accountID].grossBalance[ETH] += msg.value;
      accountData[_accountID].netBalance[ETH] += msg.value;
    }

    // Emit event for ETH deposit
    emit ETHDeposited(_accountID, msg.value, block.timestamp);
    return true;
  }  

  /**
   * @notice Moves tokens from one account to another
   * @dev This is not a multi-sig operation, but should be permissioned to a role
   * @dev Multi-sig mechanism can be modified to allow internal transfers to require
   * multi-sig authorization, but will increase contract complexity substantially.

    UNIT TESTS:
    it("Should not transfer tokens from account with insufficient netBalance")
    it("Should update both accounts' balances correctly")
   */
  function internalTransfer(
    bytes32 _ticker,
    uint256 _amount, 
    uint256 _accountIDFrom, 
    uint256 _accountIDTo,
    uint256 _txnID
  ) external returns(bool votePassed, bytes32 requestID, uint256 txnID) {
    // Retrieve data for sending account
    AccountData storage account = accountData[_accountIDFrom];

    // Check caller's account role
    _checkRole(account.role);


    // Internal transfers from Public accounts can only be initiated by Public Admins
    if(account.role == PUBLIC){
      require(hasRole(PUBLICADMIN), "Only Public Admin");
    }

    // Store Request multi-sig data
    RequestData memory request = requestHistory[_txnID];
    requestID = request.requestID;
    txnID = _txnID;
    votePassed = false;

    // Hash the function's inputs and function name
    bytes32 inputHash = keccak256(abi.encodePacked(_ticker, _amount, _accountIDFrom, _accountIDTo));
    bytes32 funcName = keccak256(abi.encodePacked("internalTransfer"));
    
    // Check that sending account has sufficient balance
    require(
      account.netBalance[_ticker] >= _amount &&
      account.grossBalance[_ticker] >= _amount, // This may not be necessary
      "Insufficient balance"
    );
    // Check caller submitted correct inputs for given txnID
    if(_txnID != 0){
      require(request.inputsHash == inputHash, "Wrong inputs");
    }

    // If Admin submitted new request, then submit new request and return request data
    if(_txnID == 0){
      // Submit new RequestData
      (requestID, txnID) = _submitRequest(funcName, inputHash, account.role, _createEmptyTxn());

      // Adjust sending account's net balance
      account.netBalance[_ticker] -= _amount;

      // Emit alert for internal transfer
      emit InternalTransfer(
        requestID, 
        txnID,
        _ticker, 
        _amount, 
        _accountIDFrom, 
        _accountIDTo, 
        msg.sender, 
        block.timestamp
      );
      assert(
        account.netBalance[_ticker] <= 
        account.grossBalance[_ticker]
      ); //REMOVE
      // Return RequestData data
      return (votePassed, requestID, txnID);
    }
    // Otherwise, run multi-sig confirmation, proceed with transfer if approved
    else if(iMultiSig.confirmRequest(requestID, msg.sender, account.role)){

      // Update remaining internal balances
      accountData[_accountIDFrom].grossBalance[_ticker] -= _amount;
      accountData[_accountIDTo].grossBalance[_ticker] += _amount;
      accountData[_accountIDTo].netBalance[_ticker] += _amount;
      votePassed = true;

      assert(
        account.netBalance[_ticker] <= 
        account.grossBalance[_ticker]
      ); //REMOVE
      assert(
        accountData[_accountIDFrom].netBalance[_ticker] <= 
        accountData[_accountIDFrom].grossBalance[_ticker]
      ); //REMOVE
      return  (votePassed, requestID, txnID);
    }
  }

  /**
   * @notice Deposits ETH into default account 
    it("Should update grossBalance and netBalance when ETH is deposited")
   */
  receive() external payable {
    // Update default account's balances
    accountData[defaultAccountID].grossBalance[ETH] += msg.value;
    accountData[defaultAccountID].netBalance[ETH] += msg.value;    

    emit ETHDeposited(defaultAccountID, msg.value, block.timestamp);
  }

  // Throws error message when invalid function is called with/without ETH
  fallback() external payable {
    revert("Invalid function");
  }

  /**
   * @notice Adds or modifies an ERC20 token, requires multi-sig approval
   * @dev When this function is called with _txnID = 0, a new multi-sig request will be
   * submitted using the function's inputs, and a new requestID and txnID will be returned.
   * To confirm this request, Admins must provide the same inputs and the txnID that was
   * returned from submission. When enough signatures are gathered, the function will return
   * votePassed = true and will fire appropriate events.
   *
   * @param _ticker ERC20 ticker symbol, cannot be ETH
   * @param _tokenAddress ERC20 contract address, cannot be address(this)
   * @param _txnID Other request ID to confirm, _txnID = 0 will submit new request
   *
   * @return votePassed Bool flag indicating if function call passed multi-sig vote
   * @return requestID Multi-sig ID for this request which tracks approval status
   * @return txnID Index value of requestHistory array, stores requestID
   *
   * Fires ERC20Added event when a new ERC20 token was added
   * Fires ERC20Modified event when an existing ERC20 token's address was updated

    UNIT TESTS:
    it("Should revert for ETH ticker")
    it("Should assign/reassign address correctly")
   */
  function modifyToken(
    bytes32 _ticker, 
    address _tokenAddress, 
    uint256 _txnID
  ) external onlyRole(ADMIN) returns (bool votePassed, bytes32 requestID, uint256 txnID) {
    //*** INITIALIZE ***\\
    // Store RequestData data
    RequestData memory request = requestHistory[_txnID];
    requestID = request.requestID;
    txnID = _txnID;
    votePassed = false;

    // Hash the function's inputs
    bytes32 inputHash = keccak256(abi.encodePacked(_ticker, _tokenAddress));
    bytes32 funcName = keccak256(abi.encodePacked("modifyToken"));
    // Retrieve token's address
    address tokenAddress = tokenAddressMap[_ticker];

    //*** CHECKS ***\\
    // Check caller is not overriding ETH assignments
    require(
      _ticker != ETH &&
      tokenAddress != address(this) &&
      _tokenAddress != address(this),
      "Cannot override ETH assignments"
    );

    // Check caller provided correct inputs
    if(_txnID != 0){
      require(request.inputsHash == inputHash, "Wrong inputs");
    }

    //*** EFFECTS ***\\
    // No effects needed at this time pending multi-sig approval

    //*** INTERACTIONS ***\\
    // If _txnID is 0, then submit a new Request, fire event, and return
    if(_txnID == 0){
      (request.requestID, txnID) = _submitRequest(funcName, inputHash, ADMIN, _createEmptyTxn());

      // Fire correct event depending on whether token is new or existing
      // If token is new, then fire ERC20Added event
      if(tokenAddress == address(0)){
        emit ERC20Added({
          requestID: request.requestID,
          txnID: txnID,
          ticker: _ticker, 
          tokenAddress: _tokenAddress,
          adminCaller: msg.sender,
          timestamp: block.timestamp
        });
      }
      // Otherwise, emit ERC20Modified event
      else {
        emit ERC20Modified({
          requestID: request.requestID,
          txnID: txnID,
          ticker: _ticker, 
          oldAddress: tokenAddressMap[_ticker],
          newAddress: _tokenAddress,
          adminCaller: msg.sender,
          timestamp: block.timestamp
        });
      }

      return (votePassed, request.requestID, txnID);
    }

    // Run multi-sig check, fire appropriate event and update token address if vote passes
    if(iMultiSig.confirmRequest(requestID, msg.sender, ADMIN)){
      votePassed = true;

      // Update token's on-chain contract address
      tokenAddressMap[_ticker] = _tokenAddress;

      // Return with RequestData data
      return (votePassed, request.requestID, _txnID);
    }

    // If function has not returned, then multi-sig has not approved yet
    return (votePassed, request.requestID, _txnID);
  }

  /**
   * @notice Returns pending transaction IDs, sorted from most recent to oldest
   * @dev While this is a view function, it is gas-optimized for smart contract use.
   * An alternative design can be made which does not use a state variable to track
   * number of pending transactions, but it adds a second loop to this function and
   * requires iterating through entire requestHistory array, which may be rejected by a
   * node even if it is view-only, should requestHistory contain hundreds/thousands of 
   * elements.
   * @dev Front end: Feed this function's outputs into the requestHistory array's public
   * getter function to produce an array of all pending transaction details.
   */
  function getPendingIDs() public view returns (uint256[] memory pendingTxnIDs) {
    // Check for pending requests
    require(pendingTxns > 0, "No pending requests");

    // Initialize variables
    uint256 j = 0; // Index counter for pendingTxnIDs
    uint i = requestHistory.length; // Starting point for loop counter
    // Define size of pendingTxnIDs as pendingTxns
    pendingTxnIDs = new uint256[](pendingTxns);

    // Unchecked because i underflow is prevented by loop condition
    unchecked {
      // Populate pendingTxnIDs
      while(j < pendingTxns && i > 0){
        // Store transaction and request approval status
        RequestData memory request = requestHistory[i - 1];

        // If transaction is inactive, then skip to next transaction
        if (!request.requestActive) {
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
