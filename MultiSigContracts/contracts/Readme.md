**Description**
A collection of multi-signature contracts in various forms for different purposes. Contracts are created for variations on asset management and multi-sig function calling.

**SimpleMultiSig and SimpleMultiSigV2**
Multi-sig wallet contracts with the multi-signature voting and confirmation mechanisms implemented locally. While these are the "simplest" to build, these contracts are actually more complex in terms of code due to the local implementation of the multi-sig mechanism, and thus take up more space.

Simple Multi-Sig V1 only handles ETH, while Simple Multi-Sig V2 handles ETH and ERC20 tokens.


**MultiSigContract**
This is a template design for a multi-sig contract which secures function calls and stores input values on-chain. This contract can get very messy due to each function requiring a struct to store the inputs, but if on-chain storage of the individual inputs is important then this template may be useful. However, the General Multi-Sig design would be preferred, which uses events to track function inputs off-chain.


**GeneralMultiSigV1, GeneralMultiSigV2, GeneralMultiSigV3**
Universal multi-sig voting mechanisms that are used for securing functions rather than assets, but can be implemented to manage assets. These contracts are comparatively simpler than the basic multi-sig contracts.

V1 is implemented internally, while V2 and V3 are implemented externally. V1 abstracts the multi-sig mechanism while keeping it internal to the contract using it. V2 and V3 out-sources the multi-sig mechanism to an external contract, and can independently track multiple unrelated smart contracts that need multi-sig voting but may not have enough room to include such a mechanism.

V1 and V2 only allow for one set of Admins to submit and confirm requests, while V3 implements a role system.

The idea of V2 and V3 is to eliminate the need for an internal multi-sig mechanism from any contract, reducing code size and complexity and thus permitting more sophisticated functionality within the 24kb size limit. V2 assumes the calling contract has only a single role assigned for multi-sig votes, while V3 facilitates role-based voting.

The primary advantage of implementing the role system in V3 is that different multi-sig ratios and voting requirements can be established for different roles. This allows a single organization to divide a treasury/budget into smaller teams or roles, who can use multi-sig voting to withdraw assets independently of other teams. There are no size limits on the number of role holders that can exist, permitting the implementation of DAOs with this design.

V3 is the most advanced, and is designed to be available to the general public. Requests are identified by their hashed function inputs, their local transaction IDs within the calling contract, and the access control role assigned to the multi-sig request. These requests are organized by the calling contract's address.

This mechanism is intended to be implemented for ANY function regardless of its inputs, without the need for a submit/confirm mechanism or on-chain input data storage as seen in Multi-Sig Contract. Instead, functions that need to be secured via multi-sig can be called directly by users along with the correct inputs, and the multi-sig contract will be called as part of the function's normal operation. If a user submits the wrong inputs, then the transaction will revert.

To submit a new function request, the caller calls the submit function, and if no role system is implemented then they use 0 for the role ID. To vote on a request, callers use the confirm function, and must provide the requestID, a hash of the function's inputs, and the calling contract's local transaction ID used for storing on-chain data. If the contract does not keep an array of on-chain transaction records, then use 0 for the transaction ID.

The multi-sig contract will return a true or false flag if the multi-sig request was approved or not. Calling contracts only need to implement an if/else block to secure functions via multi-sig.


**Treasury, TreasuryV2, TreasuryV3**
These are all examples of asset management contracts secured by multi-sig authorization.

Treasury V1 and V2 are single-account contracts, while Treasury V3 is a multi-account and multi-role contract.

Treasury V1 only secures withdrawal/transfer requests via multi-sig, while administrative actions--such as adding a new ERC20 token or new Admin--are handled by the Admins or Owner of the contract.

Treasury V2 implements a multi-sig system for administrative actions alongside the withdrawal/transfer requests, while still maintaining a single-account system. This system is internal to the contract, and inherits from General Multi-Sig V1.

Treasury V3 includes the multi-sig system of Treasury V2, but extends the functionality into multiple accounts managed by multiple roles within the calling contract, each of which manages their own multi-sig voting. Treasury V3 utilizes General Multi-Sig V3's external voting mechanism, and serves as an example of how to implement this contract design.


**IVotingRequirements**
Interface for the only function that is required to use the General Multi-Sig contract. Implement the function votesRequired to return the number of votes required to pass a multi-sig check.

For contracts that are a single team managing a contract of assets, ignore the input value and just return the number of votes required to pass the check.

For contracts that implement a multi-team role system, use the input value and a mapping to return the number of votes required by holders of that role to pass the check.



