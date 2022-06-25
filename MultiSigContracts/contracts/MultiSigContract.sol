// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./WalletAdmins.sol";
import "./OpenZeppelinDependencies/IERC20.sol";

contract MultiWallet is WalletAdmins {
  
  /*** MULTI-SIG STRUCT AND DATA STORAGE ***\\
  /**
   * @notice Function call request, general request struct stored in request history array
   * @dev This struct is needed for the multi-sig mechanism, and prevents the need for
   * multiple arrays for each function's parameters.
   *
   * @param funcID Function parameter ID, corresponds to funtion parameter structs
   * @param approvalStatus Approval status: Submitted, Pending, Approved, Cancelled
   */
  struct functionCallRequest {
    uint8 funcID;
    APPROVE approvalStatus;
  }

  // Approval status enum
  enum APPROVE { SUBMITTED, PENDING, APPROVED, CANCELLED }

  // History of all withdrawal requests:
  functionCallRequest[] public functionCallHistory;


  //*** FUNCTION PARAMETER STRUCTS AND MAPPINGS ***\\
  /**
   * @notice Function input parameters for funcID 1, IERC20.transfer
   */
  struct transferParams {
    address contractAddress;
    address to;
    uint amount;
  }

  /**
   * @notice Function input parameters for funcID 2, IERC20.transferFrom
   */
  struct transferFromParams {
    address contractAddress;
    address from;
    address to;
    uint amount;
  }

  // Maps function request ID to its input parameter struct
  mapping(uint => transferParams) public transferReqParams; // Function ID 1
  mapping(uint => transferFromParams) public transferFromReqParams; // Function ID 2
  //mapping(uint => <function name>Params) public <function name>Request;


  //*** EVENTS ***\\
  // Fires when user submits new function call request
  event RequestSubmitted(uint indexed funcReqID, uint funcParamsID, uint timestamp);
  // Lists all parameters for IERC20.transfer request
  event FunctionParams1(uint indexed funcReqID, address to, uint amount);
  // Lists all parameters for IERC20.transferFrom request
  event FunctionParams2(uint indexed funcReqID, address from, address to, uint amount);

  // Fires when request is approved
  event RequestApproved(uint indexed requestID, uint timestamp);
  // Fires when request is cancelled by user or Admin
  event RequestCancelled(uint indexed requestID, address caller, uint timestamp);
  // Fires when Admin approves request
  event AdminApproved(uint indexed requestID, address admin, uint timestamp);

  constructor(
    address[] memory _admins, 
    uint _numerator, 
    uint _denominator
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
   */
  function submitTransferReq(address _contractAddress, address _to, uint _amount) external returns (bool success, uint requestID) {
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
    transferParams(
      _contractAddress,
      _to,
      _amount
    );

    // Add function request to request history array
    functionCallHistory.push(pendingRequest);
    // Map requestID to its transferParams struct
    transferReqParams[requestID] = requestParams;

    // Emit events, return success bool
    emit RequestSubmitted(requestID, 1, block.timestamp);
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
   */
  function submitTransferFromReq(address _contractAddress, address _from, address _to, uint _amount) external returns (bool success, uint requestID) {
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
    transferFromParams(
      _contractAddress,
      _from,
      _to,
      _amount
    );

    // Add function request to request history
    functionCallHistory.push(pendingRequest);
    // Map requestID to its transferFromParams struct
    transferFromReqParams[requestID] = requestParams;

    // Emit events, return success bool
    emit RequestSubmitted(requestID, 2, block.timestamp);
    success = true;
  }  

  // Confirm request, only Admins may call
  function confirmTransfer(uint _requestID) external onlyAdmin returns (bool funcApproved) {
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
      IERC20(transferFromReqParams[_requestID].contractAddress)
      .balanceOf(transferFromReqParams[_requestID].from) 
      >= transferFromReqParams[_requestID].amount,
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
    if(_requestApproval(request.funcID)) funcApproved = true;
    else funcApproved = false;
  }

  // Tallies up Admin approvals for request, performs request if multi-sig requirement is met
  function _requestApproval(uint _requestID) private returns (bool) {
    // 0. Initialize local variables
    uint numApproved = 0;
    functionCallRequest memory request = functionCallHistory[_requestID];

    //*** ADMIN AND SANITY CHECKS WERE COMPLETED IN PARENT FUNCTION ***\\

    // 1. Iterate through admins array and tally up approvals
    for (uint i = 0; i < admins.length; i++) {
      // Tertiary operator: If Admin approved then increment counter, if not then leave alone
      adminApproved[admins[i]][_requestID] ?
        numApproved++ :
        numApproved;
    }

    // 2. If approvals do not meet requirement, then return from function with false flag
     // Check for this first to save gas on condition checking
    if (numApproved < adminsRequired) return false;

    // 3. If previous condition was not met, then approvals met requirement, function may proceed

    //*** EFFECTS ***\\      
    // Update request's approval status to Approved
    functionCallHistory[_requestID].approvalStatus = APPROVE.APPROVED;

    // Emit approval event
    emit RequestApproved(_requestID, block.timestamp);

    //*** INTERACTIONS ***\\
    // Function ID 1 (transfer)
    if(request.funcID == 1){
      // Retrieve and store input parameters for IERC20.transfer
      transferParams memory params = transferReqParams[_requestID];

      // Call IERC20.transfer using parameters from params
      if(IERC20(params.contractAddress).transfer(params.to, params.amount)){
        return true;
      }
      return false;
    }

    // Function ID 2 (transferFrom)
    if(request.funcID == 2){
      // Retrieve and store input parameters for IERC20.transferFrom
      transferFromParams memory params = transferFromReqParams[_requestID];

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
  function cancelRequest(uint _requestID) external onlyAdmin returns(bool) {
    // Declare local variables
    functionCallRequest memory request = functionCallHistory[_requestID];

    // Check request has not been approved
    require(request.approvalStatus != APPROVE.APPROVED, "Request approved");
    // Check request has not been cancelled
    require(request.approvalStatus != APPROVE.CANCELLED, "Request cancelled");

    // Update request approval status to Cancelled
    functionCallHistory[_requestID].approvalStatus = APPROVE.CANCELLED;

    // Emit cancellation alert
    emit RequestCancelled(_requestID, msg.sender, block.timestamp);
    return true;
  }

  // Returns pending request IDs
  function getPending() public view returns (uint[] memory pendingTxnIDs) {
    // 0. Initialize arrayLength variable
    uint arrayLength = 0;

    // 1. Tally number of pending transactions to find arrayLength
    for (uint i = 0; i < functionCallHistory.length; i++) {
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

    // 2a. Define size of pendingTxnIDs using arrayLength found in step 1
    pendingTxnIDs = new uint[](arrayLength);

    // 2b. Populate each pendingTxnIDs array element
    for (uint i = 0; i < arrayLength; i++) {
      // Store request in local memory
      functionCallRequest memory request = functionCallHistory[i];

      // If request was Approved or Cancelled, then skip to next request
      if (
        request.approvalStatus == APPROVE.APPROVED ||
        request.approvalStatus == APPROVE.CANCELLED
        ) {
          continue;
      }

      // If request was not skipped, then add request ID to pendingTxnIDs
      pendingTxnIDs[i] = request.funcID;      
    }

    // 3. Return array of funcIDs
    return pendingTxnIDs;
  }



}
