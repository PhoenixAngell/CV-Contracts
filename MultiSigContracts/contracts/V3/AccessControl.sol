/**
 * @dev Modified variant of OpenZeppelin's AccessControl contract module.
 * Changed:
 * - RoleData struct now includes data for multi-signature voting
 * - _roles was renamed to roleData for consistent style
 * - Added three hard-coded roles for PUBLIC, PUBLICADMIN, and ADMIN
 * - Added overloaded variant of _checkRole to check for PUBLIC accounts
 */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./../OpenZeppelinDependencies/IAccessControl.sol";
import "./../OpenZeppelinDependencies/Context.sol";
import "./../OpenZeppelinDependencies/Strings.sol";
import "./../OpenZeppelinDependencies/ERC165.sol";

/**
 * @dev Contract module that allows children to implement role-based access
 * control mechanisms. This is a lightweight version that doesn't allow enumerating role
 * members except through off-chain means by accessing the contract event logs. Some
 * applications may benefit from on-chain enumerability, for those cases see
 * {AccessControlEnumerable}.
 *
 * Roles are referred to by their `bytes32` identifier. These should be exposed
 * in the external API and be unique. The best way to achieve this is by
 * using `public constant` hash digests:
 *
 * ```
 * bytes32 public constant MY_ROLE = keccak256("MY_ROLE");
 * ```
 *
 * Roles can be used to represent a set of permissions. To restrict access to a
 * function call, use {hasRole}:
 *
 * ```
 * function foo() public {
 *   require(hasRole(MY_ROLE, msg.sender));
 *   ...
 * }
 * ```
 *
 * Roles can be granted and revoked dynamically via the {grantRole} and
 * {revokeRole} functions. Each role has an associated admin role, and only
 * accounts that have a role's admin role can call {grantRole} and {revokeRole}.
 *
 * By default, the admin role for all roles is `DEFAULT_ADMIN_ROLE`, which means
 * that only accounts with this role will be able to grant or revoke other
 * roles. More complex role relationships can be created by using
 * {_setRoleAdmin}.
 *
 * WARNING: The `DEFAULT_ADMIN_ROLE` is also its own admin: it has permission to
 * grant and revoke this role. Extra precautions should be taken to secure
 * accounts that have been granted it.
 */
abstract contract AccessControl is Context, IAccessControl, ERC165 {
  /**
   * @dev Overridden from AccessControl
   * @param members Maps addresses to users with this role
   * @param adminRole Role that can assign or remove this role to or from users
   * @param roleCount Number of role holders, used for multi-sig threshold
   * @param ratio Multi-sig consensus ratio: ratio[0] = numerator, ratio[1] = denominator
   */
  struct RoleData {
  mapping(address => bool) members;
  bytes32 adminRole; // Admin role that can add or remove role holders
  uint256 roleCount; // Total role holders, used for multi-sig threshold
  uint256[2] ratios; // Multi-sig ratios: ratio[0] = numerator, ratio[1] = denominator
  }

  // Maps role ID to its RoleData
  mapping(bytes32 => RoleData) public roleData;

  bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

  // Role for non-permissioned accounts
  bytes32 public immutable PUBLIC;
  // Role for managing non-permissioned accounts
  bytes32 public immutable PUBLICADMIN;
  // Role for administrative functions
  bytes32 public immutable ADMIN;

  constructor(  
    address[][] memory _admins,
    string[] memory _roles
  ) {
    // Set up immutable roles
    PUBLIC = keccak256(abi.encodePacked("PUBLIC"));
    PUBLICADMIN = keccak256(abi.encodePacked("PUBLICADMIN"));
    ADMIN = keccak256(abi.encodePacked("ADMIN"));


    // Setup all accounts, admin roles, and multi-sig ratios
    for(uint256 i = 0; i < _roles.length; i++){
    // Hash the role's name
    bytes32 role = keccak256(abi.encodePacked(_roles[i]));

    // Setup grant role to admins
    for(uint256 j = 0; j < _admins[i].length; j++){
      _setupRole(role, _admins[i][j]);
      roleData[role].roleCount++; // Increment counter for multi-sig threshold
    }

    }

  }

  /**
   * @dev Modifier that checks that an account has a specific role. Reverts
   * with a standardized message including the required role.
   *
   * The format of the revert reason is given by the following regular expression:
   *
   *  /^AccessControl: account (0x[0-9a-f]{40}) is missing role (0x[0-9a-f]{64})$/
   *
   * _Available since v4.1._
   */
  modifier onlyRole(bytes32 role) {
    _checkRole(role, _msgSender());
    _;
  }

  /**
   * @dev See {IERC165-supportsInterface}.
   */
  function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
    return interfaceId == type(IAccessControl).interfaceId || super.supportsInterface(interfaceId);
  }

  /**
   * @dev Returns `true` if `account` has been granted `role`.
   */
  function hasRole(bytes32 role, address account) public view virtual override returns (bool) {
    return roleData[role].members[account];
  }

  /**
   * @dev Revert with a standard message if `account` is missing `role`.
   *
   * The format of the revert reason is given by the following regular expression:
   *
   *  /^AccessControl: account (0x[0-9a-f]{40}) is missing role (0x[0-9a-f]{64})$/
   */
  function _checkRole(bytes32 role, address account) internal view virtual {
    if (!hasRole(role, account)) {
      revert(
        string(
          abi.encodePacked(
            "AccessControl: account ",
            Strings.toHexString(uint160(account), 20),
            " is missing role ",
            Strings.toHexString(uint256(role), 32)
          )
        )
      );
    }
  }

  /**
  * @notice Checks if user has appropriate role to interact with account
  * @dev Overridden from AccessControl, the role is not known beforehand, but the accountID
  * has a role associated with it. The user must match the role assigned to the account.
  */
  function _checkRole(bytes32 _accountRole) internal view {

    // Check if account has public role
    if (_accountRole == PUBLIC){
    return; // Public accounts do not require caller to have a role
    }
    // Check if user has role required for account
    else if (!hasRole(_accountRole, msg.sender)) {
      revert(
        string(
          abi.encodePacked(
            "AccessControl: user ",
            Strings.toHexString(uint160(msg.sender), 20),
            " is missing role ",
            Strings.toHexString(uint256(_accountRole), 32)
          )
        )
      );
    }
  }

  /**
   * @dev Returns the admin role that controls `role`. See {grantRole} and
   * {revokeRole}.
   *
   * To change a role's admin, use {_setRoleAdmin}.
   */
  function getRoleAdmin(bytes32 role) public view virtual override returns (bytes32) {
    return roleData[role].adminRole;
  }

  /**
   * @dev Grants `role` to `account`.
   *
   * If `account` had not been already granted `role`, emits a {RoleGranted}
   * event.
   *
   * Requirements:
   *
   * - the caller must have ``role``'s admin role.
   */
  function grantRole(bytes32 role, address account) public virtual override onlyRole(getRoleAdmin(role)) {
    _grantRole(role, account);
  }

  /**
   * @dev Revokes `role` from `account`.
   *
   * If `account` had been granted `role`, emits a {RoleRevoked} event.
   *
   * Requirements:
   *
   * - the caller must have ``role``'s admin role.
   */
  function revokeRole(bytes32 role, address account) public virtual override onlyRole(getRoleAdmin(role)) {
    _revokeRole(role, account);
  }

  /**
   * @dev Revokes `role` from the calling account.
   *
   * Roles are often managed via {grantRole} and {revokeRole}: this function's
   * purpose is to provide a mechanism for accounts to lose their privileges
   * if they are compromised (such as when a trusted device is misplaced).
   *
   * If the calling account had been revoked `role`, emits a {RoleRevoked}
   * event.
   *
   * Requirements:
   *
   * - the caller must be `account`.
   */
  function renounceRole(bytes32 role, address account) public virtual override {
    require(account == _msgSender(), "AccessControl: can only renounce roles for self");

    _revokeRole(role, account);
  }

  /**
   * @dev Grants `role` to `account`.
   *
   * If `account` had not been already granted `role`, emits a {RoleGranted}
   * event. Note that unlike {grantRole}, this function doesn't perform any
   * checks on the calling account.
   *
   * [WARNING]
   * ====
   * This function should only be called from the constructor when setting
   * up the initial roles for the system.
   *
   * Using this function in any other way is effectively circumventing the admin
   * system imposed by {AccessControl}.
   * ====
   *
   * NOTE: This function is deprecated in favor of {_grantRole}.
   */
  function _setupRole(bytes32 role, address account) internal virtual {
    _grantRole(role, account);
  }

  /**
   * @dev Sets `adminRole` as ``role``'s admin role.
   *
   * Emits a {RoleAdminChanged} event.
   */
  function _setRoleAdmin(bytes32 role, bytes32 adminRole) internal virtual {
    bytes32 previousAdminRole = getRoleAdmin(role);
    roleData[role].adminRole = adminRole;
    emit RoleAdminChanged(role, previousAdminRole, adminRole);
  }

  /**
   * @dev Grants `role` to `account`.
   *
   * Internal function without access restriction.
   */
  function _grantRole(bytes32 role, address account) internal virtual {
    if (!hasRole(role, account)) {
      roleData[role].members[account] = true;
      emit RoleGranted(role, account, _msgSender());
    }
  }

  /**
   * @dev Revokes `role` from `account`.
   *
   * Internal function without access restriction.
   */
  function _revokeRole(bytes32 role, address account) internal virtual {
    if (hasRole(role, account)) {
      roleData[role].members[account] = false;
      emit RoleRevoked(role, account, _msgSender());
    }
  }
}
