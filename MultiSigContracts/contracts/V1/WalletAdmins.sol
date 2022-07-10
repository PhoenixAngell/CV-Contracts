/**
Simple contract for tracking, adding, and removing Admins with multi-sig permissions
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./../OpenZeppelinDependencies/Ownable.sol";

contract WalletAdmins is Ownable {

  // Maps Admin address and txID for approval:
  mapping(address => mapping(uint => bool)) public adminApproved;
  // Maps Admin addresses with Admin status
  mapping(address => bool) public isAdmin;

  // All admins with multi-sig permissions
  address[] public admins;

  // Number of Admin signatures required
  uint numerator;
  uint denominator;
  uint adminsRequired = (admins.length * numerator) / denominator;

  // Note Numerator is allowed to be 0 until modified, which disables multi-sig temporarily,
  // but once numerator has been set it cannot be set back to 0 again.
  constructor(address[] memory _admins, uint _numerator, uint _denominator) {
    // Sanity check
    require(
      _denominator != 0 &&
      _numerator <= _denominator, 
      "Impossible ratio"
    );

    // Assign signature requirement ratio
    numerator = _numerator;
    denominator = _denominator;

    // Add contract owner as first Admin
    admins.push(msg.sender);
    isAdmin[msg.sender] = true;

    // Add each Admin from _admins
    for(uint i = 0; i < _admins.length; i++){
      admins.push(_admins[i]);
      isAdmin[_admins[i]] = true;
    }
  }

  modifier onlyAdmin() {
    require(isAdmin[msg.sender], "Only Admins");
    _;
  }

  // Adds a new Admin address, only the contract owner can call
   // May override to implement multi-sig mechanism in child contract
  function addAdmin (address _address) public virtual onlyOwner() returns (uint adminID) {
    // Assign adminID to its index position in the admins array
    adminID = admins.length;
    // Push _address to admins array
    admins.push(_address);
    // Update Admin's isAdmin status
    isAdmin[_address] = true;
  }

  // Removes an Admin address, only the contract owner can call
   // May override to implement multi-sig mechanism in child contract
  function removeAdmin(uint _adminID) public virtual onlyOwner() {
    // Store local variables
    address adminRemoved = admins[_adminID];

    // Perform sanity checks
    require(adminRemoved != owner(), "Can't remove owner");

    // Remove Admin's isAdmin status
    isAdmin[admins[_adminID]] = false;
    
    // Use bubble sorting algorithm to shift adminRemoved to end, then pop
    for(uint i = 0; i < admins.length; i++){
      
      // 1. Check if admins[i] is adminRemoved, skip rest of logic if false
       // If adminRemoved is found, then move on to step 2
      if(admins[i] != adminRemoved) continue;

      // 2. Check if i is end of array
      if(i == admins.length - 1){
        // 2a. If i is end of array, then check if admins[i] is adminRemoved
        if(admins[i] == adminRemoved){
          admins.pop(); // If true, then pop adminRemoved from array
        }
        // 2b. Whether true or false, break the loop
        break;
      }

      // 3. If admins[i] is adminRemoved and is not end of array, then perform bubble sort
      else {
        admins[i] = admins[i + 1];
        admins[i + 1] = adminRemoved;
      }
    }
  }

  // Modifies the ratio required for multi-sig approval
  function modifySignatureRatio(uint _numerator, uint _denominator) external virtual onlyOwner() returns(bool) {
    // Check caller is submitting different numbers than already in use
    require(_numerator != numerator || _denominator != denominator, "Nothing modified");
    // Check caller is not passing an impossible ratio
    require(
      _denominator != 0 &&
      _numerator != 0 &&
      _numerator <= _denominator, 
      "Impossible ratio"
    );

    // Update ratio numbers
    numerator = _numerator;
    denominator = _denominator;

    return true;
  }

}
