pragma solidity 0.8.0;

import "./DEXGetters.sol";
import "./DEX.sol";

import "./OpenZeppelinDependencies/IERC20.sol";
import "./OpenZeppelinDependencies/SafeMath.sol";
import "./OpenZeppelinDependencies/Ownable.sol";
import "./DEXGetters.sol";


//Create event for transferring ETH to/from private address;

contract DEXWallet is Ownable, DEXGetters {
  using SafeMath for uint256;

  struct Token {
      bytes32 ticker;
      address tokenAddress;
    }

  mapping(bytes32 => Token) public tokenMapping;
  mapping(address => mapping(bytes32 => uint256)) public balances;

  bytes32[] public tokenList;
  bytes32 public ETH = keccak256(abi.encodePacked("ETH"));

  modifier tokenExists(string memory ticker_){
    bytes32 ticker = _keccak256(ticker_);
    if (ticker != ETH){
    require(tokenMapping[ticker].tokenAddress != address(0), "Token non-existent");
    }
    _;
  }

  function addToken(string memory ticker_, address _tokenAddress) external onlyOwner {
    bytes32 _ticker = _keccak256(ticker_);
    tokenMapping[_ticker] = Token(_ticker,_tokenAddress);
    tokenList.push(_ticker);
  }

  function deposit(string memory ticker_, uint _amount) external tokenExists(ticker_) {
    bytes32 _ticker = _keccak256(ticker_);
    balances[msg.sender][_ticker] = balances[msg.sender][_ticker].add(_amount);
    IERC20(tokenMapping[_ticker].tokenAddress).transferFrom(msg.sender, address(this), _amount);
  }

  function depositETH() external payable {
    require(msg.value > 0, "Error: value <= 0");
    uint _value = msg.value;
    balances[msg.sender][ETH] = balances[msg.sender][ETH].add(_value);
  }

  function withdraw (string memory ticker_, uint _amount) external tokenExists(ticker_) {
    bytes32 _ticker = _keccak256(ticker_);
    require(balances[msg.sender][_ticker] >= _amount, "Insufficient balance");

    balances[msg.sender][_ticker] = balances[msg.sender][_ticker].sub(_amount);

    if (_ticker != ETH) {
      IERC20(tokenMapping[_ticker].tokenAddress).transfer(msg.sender, _amount);
    }
    if (_ticker == ETH) {
      payable(msg.sender).transfer(_amount);
    }
  }

  function getBalance(string memory ticker_) public view returns(uint) {
    bytes32 _ticker = _keccak256(ticker_);
    return balances[msg.sender][_ticker];
  }

}
