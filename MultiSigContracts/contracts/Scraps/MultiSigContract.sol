/**
 * @title Multi-Signature Functions
 * @author Phoenix "CryptoPhoenix" Angell
 * @notice A multi-signature contract template used for calling functions via a multi-sig mechanism and tracking the function inputs on-chain.
 * @dev Inherits from WalletAdmins, but can be implemented with any kind of access control system.
 * @dev Multi-sig mechanism is contained within this contract, which may take up too much space for multiple functions. A more effective implementation may use GeneralMultiSig.sol as an external contract, and to use this contract for its functionCallHistory array and each function's mapping.
 * @dev Uses function IDs to internally determine which mapping to use for function inputs. Each function locked with a multi-sig has its own inputs struct and a mapping to the index value of its function call request. This allows all functions locked by this contract to have their input values tracked on-chain.
 */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./../WalletAdminsV1-1.sol";
import "./../OpenZeppelinDependencies/IERC20.sol";

contract MultiSigFunction is WalletAdmins {
  
  /*** MULTI-SIG STRUCT AND DATA STORAGE ***\\
  /**
   * @notice Function call request, general request struct stored in request history array
   * @dev This struct is needed for the multi-sig mechanism, and prevents the need for
   * multiple arrays for each function's parameters.
   * @dev Each functionCallRequest is mapped to a <function name>Params struct by its index value
   *
   * @param funcID Function parameter ID, corresponds to function parameter structs
   * note There is no way a single contract can hold more than 256 parameter structs and functions, 
   * so uint8 is used to save storage
   * @param approvalStatus Approval status: Submitted, Pending, Approved, Cancelled
   */
  struct functionCallRequest {
    uint8 funcID;
    APPROVE approvalStatus;
  }

  // Approval status enum
  enum APPROVE { SUBMITTED, PENDING, APPROVED, CANCELLED }

  // History of all requests:
  functionCallRequest[] public functionCallHistory;


  //*** FUNCTION PARAMETER STRUCTS AND MAPPINGS ***\\
  /**
   * @notice Function input parameters for funcID 1, IERC20.transfer
   * @dev All parameters correspond to IERC20 parameters, except contractAddress
   *
   * @param contractAddress Address for ERC20 token contract
   */
  struct transferParams {
    uint256 amount;
    address contractAddress;
    address to;
  }

  /**
   * @notice Function input parameters for funcID 2, IERC20.transferFrom
   * @dev All parameters correspond to IERC20 parameters, except contractAddress
   *
   * @param contractAddress Address for ERC20 token contract
   */
  struct transferFromParams {
    uint256 amount;
    address contractAddress;
    address from;
    address to;
  }

  // Maps function request ID (index value) to its input parameter struct
  mapping(uint256 => transferParams) public transferParamsMap; // Function ID 1
  mapping(uint256 => transferFromParams) public transferFromParamsMap; // Function ID 2
  //mapping(uint256 => <function name>Params) public <function name>Request;


  //*** MULTI-SIG EVENTS ***\\
  // Fires when user submits new function call request
  event RequestSubmitted(uint256 indexed requestID, uint8 funcParamsID, uint256 timestamp);
  // Fires when request is approved
  event RequestApproved(uint256 indexed requestID, uint256 timestamp);
  // Fires when request is cancelled by user or Admin
  event RequestCancelled(uint256 indexed requestID, address caller, uint256 timestamp);
  // Fires when Admin approves request
  event AdminApproved(uint256 indexed requestID, address admin, uint256 timestamp);

  //*** PARAMETER EVENTS***\\
  // Lists all parameters for IERC20.transfer request
  event TransferParams(uint256 indexed requestID, address to, uint256 amount);
  // Lists all parameters for IERC20.transferFrom request
  event TransferFromParams(uint256 indexed requestID, address from, address to, uint256 amount);

  /**
   * @param _admins Array of all Admins with multi-sig permissions
   * @param _numerator Numerator of multi-sig requirement ratio
   * @param _denominator Denominator of multi-sig requirement ratio
   */
  constructor(
    address[] memory _admins, 
    uint256 _numerator, 
    uint256 _denominator
  ) WalletAdmins(_admins, _numerator, _denominator) {
    super;
  }

  /**
   * @notice Submits a function call request for IERC20.transfer
   *
   * @param _to Recipient
   * @param _amount Amount
   *
   * @return success Bool flag indicating completion of submission, not necessary
   * @return requestID Array index position of function call request
   * @dev Emits RequestSubmitted event
   * @dev Emits TransferParams event
   */
  function submitTransferReq(address _contractAddress, address _to, uint256 _amount) external returns (bool success, uint256 requestID) {
    // Declare local variables
    requestID = functionCallHistory.length;

    // Sanity checks
    require(_to != address(0), "Zero address");
    require(_amount > 0, "Zero amount");
    require(IERC20(_contractAddress).balanceOf(address(this)) >= _amount);
    // ***ADMIN PERMISSION CHECKS GO HERE, IF NEEDED*** \\

    // Create new function call request
    functionCallRequest memory pendingRequest =
    functionCallRequest(
      1, // ID 1 corresponds to IERC20.transfer
      APPROVE.SUBMITTED
    );

    // Create input parameters struct for transferParams
    transferParams memory requestParams = 
    transferParams({
      contractAddress: _contractAddress,
      to: _to,
      amount: _amount
      });

    // Add function request to request history array
    functionCallHistory.push(pendingRequest);
    // Map requestID to its transferParams struct
    transferParamsMap[requestID] = requestParams;

    // Emit events, return success bool
    emit RequestSubmitted(requestID, 1, block.timestamp);
    emit TransferParams(requestID, _to, _amount);
    success = true;
  }

  /**
   * @notice Submits a request for function ID 2: IERC20.transferFrom
   * @dev This contract must be approved before submitting transferFrom request
   *
   * @param _from Sender
   * @param _to Recipient
   * @param _amount Amount
   *
   * @return success Bool flag indicating completion of submission, not necessary
   * @return requestID Array index position of function call request
   * @dev Emits RequestSubmitted event
   * @dev Emits TransferFromParams event
   */
  function submitTransferFromReq(address _contractAddress, address _from, address _to, uint256 _amount) external returns (bool success, uint256 requestID) {
    // Declare local variables
    requestID = functionCallHistory.length;

    // Sanity checks
    require(_to != address(0), "Zero address");
    require(_amount > 0, "Zero amount");
    require(IERC20(_contractAddress).allowance(_from, address(this)) >= _amount);
    require(IERC20(_contractAddress).balanceOf(_from) >= _amount);
    // ***ADMIN PERMISSION CHECKS GO HERE, IF NEEDED*** \\

    // Create new function call request
    functionCallRequest memory pendingRequest =
    functionCallRequest(
      2, // ID 2 corresponds to IERC20.transferFrom
      APPROVE.SUBMITTED
    );

    // Create struct for inputs
    transferFromParams memory requestParams = 
    transferFromParams({
      contractAddress: _contractAddress,
      from: _from,
      to: _to,
      amount: _amount
    });

    // Add function request to request history
    functionCallHistory.push(pendingRequest);
    // Map requestID to its transferFromParams struct
    transferFromParamsMap[requestID] = requestParams;

    // Emit events, return success bool
    emit RequestSubmitted(requestID, 2, block.timestamp);
    emit TransferFromParams(requestID, _from, _to, _amount);
    success = true;
  }  

  // Confirm request, only Admins may call
  function confirmTransfer(uint256 _requestID) external onlyAdmin returns (bool requestApproved) {
    // Declare local variables
    functionCallRequest memory request = functionCallHistory[_requestID];
    APPROVE status = request.approvalStatus;
    
    //*** CHECKS ***\\
    // Check request hasn't been approved already
    require(status != APPROVE.APPROVED, "Request approved");
    // Check request hasn't been cancelled
    require(status != APPROVE.CANCELLED, "Request cancelled");
    // Check Admin has not already approved request
    require(!adminApproved[msg.sender][_requestID], "Admin approved");

    //*** ERC20 SANITY CHECK FOR TRANSFERFROM ***\\
    // Prevents a transferFrom request from being approved with insufficient balance, which
    // would require resubmitting the request and redoing the multi-sig vote if the request
    // is approved but fails to transfer.
    require(
      IERC20(transferFromParamsMap[_requestID].contractAddress)
      .balanceOf(transferFromParamsMap[_requestID].from) 
      >= transferFromParamsMap[_requestID].amount,
      "Insufficient sender balance"
      );
    //*** ADDITIONAL CONTRACT SANITY CHECKS ARE PERFORMED HERE ***\\

    //*** EFFECTS ***\\
    // If functionCallRequest was Submitted, then set to Pending    
    if(status == APPROVE.SUBMITTED) {
        functionCallHistory[_requestID].approvalStatus = APPROVE.PENDING;
      }
    
    // Update Admin's request approval
    adminApproved[msg.sender][_requestID] = true;
    // Emit event alert for Admin's approval
    emit AdminApproved(_requestID, msg.sender, block.timestamp);
    
    // Run multi-sig approval algorithm, return true if request is approved, false if not
    if(_requestApproval(request.funcID)) requestApproved = true;
    else requestApproved = false;
  }

  // Tallies up Admin approvals for request, performs request if multi-sig requirement is met
  function _requestApproval(uint256 _requestID) private returns (bool) {
    // 0. Initialize local variables
    uint256 numApproved = 0;
    functionCallRequest memory request = functionCallHistory[_requestID];

    //*** ADMIN AND SANITY CHECKS WERE COMPLETED IN PARENT FUNCTION ***\\

    // 1. Iterate through admins array and tally up approvals
     // Unchecked to save gas, overflow errors highly unlikely
    unchecked {
      for (uint256 i = 0; i < admins.length; i++) {
        // Tertiary operator: If Admin approved then increment counter, if not then leave alone
        adminApproved[admins[i]][_requestID] ?
          numApproved++ :
          numApproved;
      }
    }

    // 2. If approvals do not meet requirement, then return from function with false flag
     // Check for this first to save gas on condition checking
    if (numApproved < adminsRequired) return false;

    // 3. If previous condition was not met, then proceed with function call

    //*** EFFECTS ***\\      
    // Update request's approval status to Approved
    functionCallHistory[_requestID].approvalStatus = APPROVE.APPROVED;

    // Emit approval event
    emit RequestApproved(_requestID, block.timestamp);

    //*** INTERACTIONS ***\\
    // Function ID 1 (transfer)
    if(request.funcID == 1){
      // Retrieve and store input parameters for IERC20.transfer
      transferParams memory params = transferParamsMap[_requestID];

      // Call IERC20.transfer using parameters from params
      if(IERC20(params.contractAddress).transfer(params.to, params.amount)){
        return true;
      }
      return false;
    }

    // Function ID 2 (transferFrom)
    if(request.funcID == 2){
      // Retrieve and store input parameters for IERC20.transferFrom
      transferFromParams memory params = transferFromParamsMap[_requestID];

      // Call IERC20.transferFrom using parameters from transferFromParams
      if(IERC20(params.contractAddress).transferFrom(params.from, params.to, params.amount)){
        return true;
      }
      return false;
    }

    //*** ADDITIONAL FUNCTION ID BRANCHES WOULD GO HERE ***\\

    else return false;

  }

  // Cancel request, only user who submitted request or Admins may cancel
  function cancelRequest(uint256 _requestID) external onlyAdmin returns(bool) {
    // Declare local variables
    functionCallRequest memory request = functionCallHistory[_requestID];

    // Check request has not been approved or cancelled
    require(
      request.approvalStatus != APPROVE.APPROVED ||
      request.approvalStatus != APPROVE.CANCELLED,
      "Request approved or cancelled");

    // Update request approval status to Cancelled
    functionCallHistory[_requestID].approvalStatus = APPROVE.CANCELLED;

    // Emit cancellation alert
    emit RequestCancelled(_requestID, msg.sender, block.timestamp);
    return true;
  }

  // Returns pending request IDs
  function getPendingRequestIDs() public view returns (uint256[] memory pendingReqIDs) {
    // 0. Initialize variables
    uint256 arrayLength = 0; // Length of pendingReqIDs
    uint256 j = 0; // Index values for pendingReqIDs

    // 1. Tally number of pending transactions to find arrayLength
     // Unchecked to save gas for smart contract interactions, overflow unlikely
    unchecked {
      for (uint256 i = 0; i < functionCallHistory.length; i++) {
        // Store request in local memory
        functionCallRequest memory request = functionCallHistory[i];

          // If request was Approved or Cancelled, then skip to next request
          if (
            request.approvalStatus == APPROVE.APPROVED ||
            request.approvalStatus == APPROVE.CANCELLED
            ) {
              continue;
          }
          // If request was not skipped, then increment arrayLength     
            arrayLength++;
      }

      // 2. Create, populate, and return a static array of pending request IDs
      pendingReqIDs = new uint256[](arrayLength);

      // 2b. Populate each pendingReqIDs array element
      for (uint256 i = 0; i < arrayLength; i++) {
        // Store request in local memory
        functionCallRequest memory request = functionCallHistory[i];

        // If request was Approved or Cancelled, then skip to next request
        if (
          request.approvalStatus == APPROVE.APPROVED ||
          request.approvalStatus == APPROVE.CANCELLED
          ) {
            continue;
          }

        // If request was not skipped, then add request ID to pendingReqIDs
        pendingReqIDs[j] = request.funcID;      
        j++;
      }
    }

    // 3. Return array of funcIDs
    return pendingReqIDs;
  }



}
