These are basic multi-signature smart contracts, one for ether, and the other for ERC20 tokens.

Both contracts can hold balances for multiple users, and require a 2/3 majority Admin vote.

**MultiSigContract**
*Description:*
Multi-signature design for calling external contract functions.

*Background:*
The challenge of designing a multi-sig smart contract that calls external contract functions
is in handling function parameters. Because Solidity does not have the ability to define null
data types that can be typed later, we have to know all function inputs' data types for each
function we wish to call via multi-sig voting. This gets very messy when a general solution is 
attempted.

*Solution:*
This design uses two types of structs. One is a general function request struct, which is 
stored in an array with the index as its function request ID, and is used for coordinating 
multi-sig voting. The other type of struct contains the function parameters for each function 
we wish to call via multi-sig voting, with one unique struct for each function. The parameter 
structs are stored in mappings that map function request IDs to their respective function 
parameter structs.

This design achieves a good balance between robustness and lightweight architecture.

*Example's Implementation:*
This example calls the transfer and transferFrom functions in IERC20, with transferParams being
for transfer and transferFromParams being for transferFrom. However, this template can be used
for any function call, provided this contract has appropriate access control permissions.

Addresses that can use the multi-sig operations ("Admins") are defined in its WalletUsers parent
contract. Other access control systems can be used as well, provided they fit within contract
size limits.

*Comments and Bugs*
It is important to remember to include appropriate sanity checks for submission and confirmation
functions that are normally performed by the external contract inside the functions being called 
by the multi-sig mechanism. These functions are not called until the vote has passed, and if it
passes the vote but fails the sanity checks in the external contract then the vote will be 
"Approved" and will fire events signalling success, but will otherwise have failed.

We can either set up a Failed status and events and include additional logic (and gas) for handling
this error, or we can prevent Admins from being able to confirm a request if it falls outside the 
sanity checks required by the external contract. This implementation prevents Admins from confirming
a request if it doesn't fit the sanity checks of the external contract, which prevents the need for
a resubmission and for redoing the voting process. Instead, Admins will only have to wait for the
conditions to line back up again, and then can approve the request.

This is implemented for IERC20.transferFrom, where the sender has autonomous control over their own
token holdings and thus can accidentally--or intentionally--send tokens prior to the multi-sig vote
approving the transferFrom function. This can cause their balance to fall below the required amount,
which will run into this problem.