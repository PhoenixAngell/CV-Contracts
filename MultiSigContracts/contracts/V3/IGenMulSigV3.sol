//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IGeneralMultiSigV3 {
  function getNextRequestID(
    bytes32 _inputsHash,
    bytes32 _role
  ) external returns (bytes32 requestID);

  function submitRequest(
    bytes32 _inputsHash,
    bytes32 _role
  ) external returns(bytes32 requestID);

  function confirmRequest(
    bytes32 _requestID, 
    address _userAddress, 
    bytes32 _role
  ) external returns (bool requestApproved);

  function cancelRequest(
    bytes32 _requestID
  ) external returns (bool);

}