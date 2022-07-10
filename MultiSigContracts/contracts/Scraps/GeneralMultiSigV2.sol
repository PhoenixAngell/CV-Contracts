/**
 * @title General Multi-Sig V2
 * @author Phoenix "CryptoPhoenix" Angell
 * @notice Universal external multi-sig voting contract that can be used for any function from any contract that is secured by a multi-sig authorization from a single team, and can only be interacted with by smart contracts that have implemented IVotingRequirements.sol. Requires a hash of the function's inputs and an ID number provided by the calling contract, which add increased security and flexibility.
 * @dev Contracts that use this mechanism must implement the votesRequired function from IVotingRequirements.sol, which must be a public/external function that returns the current multi-sig threshold for the calling contract.
 * @dev V2 only allows for one role, presumed to be the Admin role, to vote on multi-sig requests.
 *
 * NOTE: This contract is obsoleted by General Multi-Sig V3, which can use a role system or no role system at all. This contract has no roles by default, and may run slightly lighter, but likely won't matter for non-Ethereum blockchains.
 */
//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./../IVotingRequirements.sol";

contract GeneralMultiSigV2 {

  /**
   * @notice Stores all necessary data for a multi-sig request
   *
   * @param requestID Request identifier, derived from hashing inputs and counter variable
   * @param votes Tally of users that have confirmed the Request
   * @param approvalStatus Multi-sig status: Pending, Approved, or Cancelled
   * @param exists Flag indicating if the Request exists or not
   * @param requestCounter Counter variable that was used to salt the requestID
   */
  struct Request {
    uint256 votes;
    uint256 requestCounter;
    bytes32 requestID;
    STATUS approvalStatus;
    bool exists;
  }

  // Approval status enum
  enum STATUS { PENDING, APPROVED, CANCELLED }

  // Maps contract addresses to their request ID's Request structs
   // Contract address => request ID => Request struct
  mapping(address => mapping(bytes32 => Request)) public requestIDMap;
  // Tracks if a user voted for a Request
   // User address => contract address => request ID => true if user voted
  mapping(address => mapping(address => mapping(bytes32 => bool))) public userApproved;

  // Counter used to salt requestIDs
  uint256 private requestIDCounter;

  //*** EVENTS ***\\
  event RequestSubmitted(
    address indexed contractAddress,
    bytes32 indexed requestID,
    uint256 timestamp
  );
  event RequestApproved(
    address indexed contractAddress, 
    bytes32 indexed requestID, 
    uint256 timestamp
  );
  event UserConfirmed(
    address indexed userAddress, 
    address indexed contractAddress, 
    bytes32 indexed requestID, 
    uint256 timestamp
  );


  // Checks that a contract's request exists, is still pending, and caller is not an EOA
  modifier checkStatus(bytes32 _requestID) {
    Request memory request = requestIDMap[msg.sender][_requestID];

    // Check that caller is not an EOA
    require(msg.sender != tx.origin, "Caller is EOA");
    // Check request exists
    require(request.exists, "Request doesn't exist");
    // Check request is pending
    require(request.approvalStatus == STATUS.PENDING, "Request closed");

    _;
  }

  /**
   * @notice Returns true if provided inputs and transaction ID for the caller are correct for the request ID
   * @dev Use this for contracts that don't use submit/confirm functions, and which need to check provided inputs
   * for accuracy before confirming a request. See TreasuryV3.sol for an example implementation.
   */
  function checkInputs(bytes32 _inputsHash, bytes32 _requestID) public view returns (bool) {
    bytes32 requestID = keccak256(
      abi.encodePacked(
        _inputsHash, 
        requestIDMap[msg.sender][_requestID].requestCounter
      ));
    if(requestID == _requestID) return true;
    else return false;
  }

   /**
    * @notice Submits a multi-sig request
    *
    * @param _inputsHash Hash of function's inputs
    *
    * @return requestID Unique ID of multi-sig request, must be stored by child contract
    */
  function submitRequest(bytes32 _inputsHash) external returns(bytes32 requestID){
    // Generate requestID from hashed function inputs, transaction ID, and request counter
    requestID = keccak256(abi.encodePacked(_inputsHash, requestIDCounter));

    // Create new Request struct
    Request memory newRequest = Request({
      requestID: requestID,
      approvalStatus: STATUS.PENDING,
      exists: true,
      requestCounter: requestIDCounter,
      votes: 0
    });

    // Map newRequest to its requestID
    requestIDMap[msg.sender][requestID] = newRequest;
    // Increment request ID counter variable
    requestIDCounter++;

    // Emit submission event and return the requestID back to the child contract
    emit RequestSubmitted(msg.sender, requestID, block.timestamp);
    return requestID;
  }

  /**
   * @notice Runs multi-sig confirmation logic
   * @dev Calling contract must provide the requestID and the address of the Admin calling it
   *
   * @param _requestID Request ID of the multi-signature vote request
   * @param _adminAddress Address of Admin calling the calling contract
   *
   * @return requestApproved Flag indicating if the request was approved (true) or is still pending (false),
   * dependent contract uses this return value to determine when to process the function.
   */
  function confirmRequest(bytes32 _requestID, address _adminAddress) external checkStatus(_requestID) returns (bool requestApproved) {
    // Check user has not already voted for the request
    require(!userApproved[_adminAddress][msg.sender][_requestID], "Already voted");
    
    // Update user's transaction approval and increment Request's vote tally
    userApproved[_adminAddress][msg.sender][_requestID] = true;
    requestIDMap[msg.sender][_requestID].votes++;
    
    // Check if Request has reached multi-sig threshold required by calling contract
    if(requestIDMap[msg.sender][_requestID].votes >= IVotingRequirements(msg.sender).votesRequired(0)) {      
      // If votes reach multi-sig requirement, then update approval status and return with true flag
      requestIDMap[msg.sender][_requestID].approvalStatus = STATUS.APPROVED;

      emit RequestApproved(msg.sender, _requestID, block.timestamp);
      return true;
    }
    // If vote is still pending, then return with false flag
    else return false;
  }

  function cancelRequest(bytes32 _requestID) external checkStatus(_requestID) returns (bool) {
    // Update request approval status to Cancelled
    requestIDMap[msg.sender][_requestID].approvalStatus = STATUS.CANCELLED;
    return true;
  }

}