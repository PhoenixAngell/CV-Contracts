pragma solidity ^0.8.0;

import "./OpenZeppelinDependencies/ERC20.sol";

contract LINK is ERC20 {
  constructor() ERC20("Chainlink", "LINK") public {
  _mint(msg.sender, 1000);
  }
}
