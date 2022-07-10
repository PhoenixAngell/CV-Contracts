/**
 * @notice Simple contract for tracking, adding, and removing Admins with multi-sig permissions
 * @dev The only difference in V2 is the adminApproved mapping uses a bytes32 ID instead of uint256
 */

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./OpenZeppelinDependencies/Ownable.sol";

contract WalletAdminsV2 is Ownable {

  // Maps addresses to Admin status
  mapping(address => bool) public isAdmin;

  // All admins with multi-sig permissions
   // Order does not matter, on-chain list only exists for public records
  address[] public admins;

  event AdminAdded(address indexed adminAdded, uint256 newAdminAddedID, uint256 timestamp);
  event AdminRemoved(address indexed adminRemoved, address adminShifted, uint256 newAdminShiftedID, uint256 timestamp);

  constructor(address[] memory _admins) {
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

  /**
   * @notice Adds a new Admin address, only the contract owner can call
   * @dev Override to implement multi-sig mechanism in child contract
   *
   * @param _adminAddress Address of Admin to add
   * 
   * @return adminID Index value for new Admin 
   */
  function addAdmin (address _adminAddress) external virtual onlyOwner() returns (uint adminID) {
    // Assign adminID to its index position in the admins array
    adminID = admins.length;
    // Push _adminAddress to admins array
    admins.push(_adminAddress);
    // Update Admin's isAdmin status
    isAdmin[_adminAddress] = true;
  }

  /**
   * @notice Removes an Admin address, only the contract owner can call. Does not preserve order of Admin addresses, but is very light on gas.
   * @dev Override to implement multi-sig mechanism in child contract
   *
   * @param _adminAddress Address of Admin to remove
   * 
   * @return movedAdminID New index value for Admin that replaced the removed Admin 
   * @return movedAdmin Admin address that replaced the removed Admin
   */
  function removeAdmin(address _adminAddress) external virtual onlyOwner() returns(uint movedAdminID, address movedAdmin) {
    // Perform sanity check
    require(_adminAddress != owner(), "Can't remove owner");

    // Remove Admin's isAdmin status
    isAdmin[_adminAddress] = false;

    // Locate _adminAddress, switch places with end of array, then pop
    for(uint i = 0; i < admins.length; i++){
      
      // 1. Check if admins[i] is _adminAddress, skip to next entry if not
      if(admins[i] != _adminAddress) continue;

      // 2. Copy final entry over current entry
      admins[i] = admins[admins.length - 1];

      // 3. Pop array, store movedAdminID and movedAdmin, then break loop
      admins.pop();
      movedAdminID = i;
      movedAdmin = admins[i];
      break;
    }
    emit AdminRemoved(_adminAddress, movedAdmin, movedAdminID, block.timestamp);
  }

}
