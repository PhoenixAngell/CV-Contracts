/**
 * @title General Multi-Sig
 * @author Phoenix "CryptoPhoenix" Angell
 * @notice Universal multi-sig voting contract that can be used for any function. V1 is inherited from, while V2 is an external contract. Requires a hash of the function's inputs and an ID number used by a child/external contract to record important data.
 * @dev This contract is not intended to keep a record of all multi-sig votes or the data for each vote's function inputs, it only facilitates the mechanism. Child contracts that inherit from this contract should have local structs and arrays that track data on-chain. This contract does map requestIDs to their Request structs, thus child contracts should store requestIDs in their on-chain data.
 * @dev This contract implements a basic Admin and Owner permissions setup, and assumes that all multi-sig requests and votes belong to a single organization without any roles or departments.
 */
//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./../WalletAdminsV1-2.sol";

contract GeneralMultiSigV1 is WalletAdminsV2 {

  /**\
   * @param requestID Request identifier, derived from hashing inputs and counter variable
   * @param approvalStatus Approval status: Pending, Approved, or Cancelled
   * @param exists Flag indicating if request exists or not
   */
  struct Request {
    bytes32 requestID;
    APPROVE approvalStatus;
    bool exists;
  }

  enum APPROVE { PENDING, APPROVED, CANCELLED }

  // Maps Request's ID to its requestHistory entry
  mapping(bytes32 => Request) public requestIDMap;
  // Maps Admin address and requestID to its approval status 
   // adminApproved = true if Admin alread voted for requestID
  mapping(address => mapping(bytes32 => bool)) public adminApproved;

  // Counter used to salt requestIDs and prevent collisions
  uint256 requestIDCounter;

  // Number of Admin signatures required
  uint numerator;
  uint denominator;
  uint adminsRequired = (admins.length * numerator) / denominator;

  event RequestSubmitted(bytes32 indexed requestID, address indexed admin, uint256 timestamp);

  /**
   * @param _admins Array of Admin users with multi-sig voting permission
   * @param _numerator Numerator of multi-signature threshold ratio
   * @param _denominator Denominator of multi-signature threshold ratio
   */
  constructor(
    address[] memory _admins, 
    uint _numerator, 
    uint _denominator
  ) WalletAdminsV2(_admins) {
    super;
    // Check for impossible ratios
    require(
      _denominator != 0 &&
      _numerator <= _denominator, 
      "Impossible ratio"
    );

    // Assign signature requirement ratio
    numerator = _numerator;
    denominator = _denominator;
  }

  // Checks that a Request exists and is still pending
  modifier checkStatus(bytes32 _requestID) {
    Request memory request = requestIDMap[_requestID];

    // Check request exists
    require(request.exists, "Request does not exist");
    // Check request is pending
    require(request.approvalStatus == APPROVE.PENDING, "Request not pending");

    _;
  }

  // Generates the next requestID using a given input hash, transaction ID, and the value of requestIDCounter
  function newRequestID(bytes32 _inputsHash, uint256 _reqIDCounter) public pure returns (bytes32){
    return keccak256(abi.encodePacked(_inputsHash, _reqIDCounter));
  }

   /**
    * @notice Submits a multi-sig request
    *
    * @param _inputsHash Hash of function's inputs
    *
    * @return requestID Unique ID of multi-sig request, must be stored by child contract
    */
  function _submitRequest(bytes32 _inputsHash) internal returns(bytes32){
    // Generate requestID from hashed function inputs, transaction ID, and request counter
    bytes32 requestID = newRequestID(_inputsHash, requestIDCounter);

    // Increment request ID counter variable
    requestIDCounter++;

    Request memory newRequest = Request({
      requestID: requestID,
      approvalStatus: APPROVE.PENDING,
      exists: true
    });

    // Map newRequest to its requestID
    requestIDMap[requestID] = newRequest;

    // Emit submission event and return the requestID back to the child contract
    emit RequestSubmitted(requestID, msg.sender, block.timestamp);
    return requestID;
  }

  /**
   * @notice Runs multi-sig confirmation logic for the given requestID
   * @dev Child contract handles return value to determine next step after multi-sig
   * has completed
   */
  function _confirmRequest(bytes32 _requestID) internal checkStatus(_requestID) returns (bool) {
    // Declare local variables
    Request memory approvedRequest = requestIDMap[_requestID];

    // Check Admin has not already approved transaction
    require(!adminApproved[msg.sender][_requestID], "Admin approved");
    
    // Update Admin's transaction approval
    adminApproved[msg.sender][_requestID] = true;
    
    // Run multi-sig algorithm
    if(_tallyVotes(approvedRequest.requestID)) {      
      // If successful, then update approval status and return with true flag
      requestIDMap[_requestID].approvalStatus = APPROVE.APPROVED;
      return true;
    }

    // If unsuccessful, then return with false flag
    else return false;
  }

  /**
   * @notice Tallies up Admin approvals for multi-sig mechanism
   * @dev Uses unchecked logic for tallying Admin approvals, as it will never overflow
   */
  function _tallyVotes(bytes32 _requestID) private view returns (bool) {
    // 0. Initialize local variables
    uint256 numApproved = 0;

    // 1. Iterate through admins array and tally up approvals
     // Unchecked because loop counter and numApproved will not exceed uint256 type size
    unchecked {
      for (uint256 i = 0; i < admins.length; i++) {
        // Tertiary operator: If Admin approved then increment counter, if not then leave alone
        adminApproved[admins[i]][_requestID] ?
          numApproved++ :
          numApproved;
      }      
    }

    // 2. If approvals did not meet requirement, then return from function with false flag
    if (numApproved < adminsRequired) {
      return false;
    }

    // 3. Otherwise, return with true flag
    return true;
  }

  function _cancelRequest(bytes32 _requestID) internal checkStatus(_requestID) returns (bool) {
    // Update request approval status to Cancelled
    requestIDMap[_requestID].approvalStatus = APPROVE.CANCELLED;
    return true;
  }

}