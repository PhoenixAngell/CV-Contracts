pragma solidity ^0.8.0;

import "./DEXWallet.sol";
import "./DEX.sol";
import "./OpenZeppelinDependencies/SafeMath.sol";

contract DEXGetters {
  using SafeMath for uint256;

  enum SIDE { BUY, SELL }
  SIDE side;

  struct Order {
    uint id;
    address trader;
    SIDE side;
    bytes32 ticker;
    uint amount;
    uint price;
}

uint public orderID = 0;
bool _orderRemoved;

Order[] orderbook;

//Each asset has two orderbooks, one for buying and one for selling;
//bytes32 is ticker symbol, and SIDE is BUY/SELL enum;
  mapping(bytes32 => mapping(SIDE => Order[])) public orderBook;
  string errorMsg = "Orderbook empty";

  //Returns bytes32 of any string;
  function _keccak256(string memory _input) public pure returns (bytes32 _output) {
      _output = keccak256(abi.encodePacked(_input));
  }

  //Getter function to retrieve orderbook for ticker/side;
    function getOrderBook(string memory ticker_, SIDE _side) public view returns(Order[] memory) {
      bytes32 _ticker = _keccak256(ticker_);
      require(orderBook[_ticker][_side].length > 0, errorMsg);
      return orderBook[_ticker][_side];
    }
    function getOrderID(string memory ticker_, SIDE _side, uint _index) public view returns(uint) {
      bytes32 _ticker = _keccak256(ticker_);
      Order[] memory _order = orderBook[_ticker][_side];
      return _order[_index].id;
    }

    function getOrderBookLength(string memory ticker_, SIDE _side) public view returns(uint) {
      bytes32 _ticker = _keccak256(ticker_);
      return orderBook[_ticker][_side].length;
    }

  //Getter function to retrieve order token amount;
    function getOrderAmount(string memory ticker_, SIDE _side, uint _index) public view returns(uint256) {
      bytes32 _ticker = _keccak256(ticker_);
      require(orderBook[_ticker][_side].length > 0, errorMsg);
      Order[] memory ORDER = orderBook[_ticker][_side];
      return ORDER[_index].amount;
    }

  //Getter function to retrieve order's ETH price per token;
    function getLimitPrice(string memory ticker_, SIDE _side, uint _index) public view returns(uint256) {
      bytes32 _ticker = _keccak256(ticker_);
      require(orderBook[_ticker][_side].length > 0, errorMsg);
      Order[] memory ORDER = orderBook[_ticker][_side];
      return ORDER[_index].price;
    }

  //Getter function to retrieve order's total ETH price;
    function getOrderPrice(string memory ticker_, SIDE _side, uint _index) public view returns(uint256) {
      bytes32 _ticker = _keccak256(ticker_);
      require(orderBook[_ticker][_side].length > 0, errorMsg);
      uint limitPrice = getLimitPrice(ticker_, _side, _index);
      uint orderAmount = getOrderAmount(ticker_, _side, _index);
      return limitPrice.mul(orderAmount);
      }

  //Getter function for calculating total ETH cost of a market order;
    function _marketBuyCost(string memory ticker_, uint256 _amount) public view returns (uint orderCost) {
      bytes32 _ticker = _keccak256(ticker_);
      Order[] memory tempORDER = orderBook[_ticker][SIDE.SELL];
      orderCost = 0;
      if(tempORDER.length == 0) {
        return orderCost;
      }
      else {
        string memory ticker = ticker_;
        for (uint i = 0; _amount >= 0; i++) {
          if (_amount >= tempORDER[i].amount) {
            uint fillPrice = getOrderPrice(ticker, SIDE.SELL, i);
            orderCost = orderCost.add(fillPrice);
            _amount = _amount.sub(tempORDER[i].amount);
          }

          if (_amount < tempORDER[i].amount && _amount > 0) {
            uint partialFillPrice = _amount * tempORDER[i].price;
            orderCost = orderCost.add(partialFillPrice);
            break;
          }
          if (i == tempORDER.length - 1) {
            break;
          }
        }
        return orderCost;
      }
    }

    //Returns total amount of orderbook;
    //Used for orders that clear out orderbook;
    function _getOrderbookAmount(string memory ticker_, SIDE _side) public view returns (uint256 totalAmount) {
      bytes32 _ticker = _keccak256(ticker_);
      Order[] memory _order = orderBook[_ticker][_side];
      totalAmount = 0;
      uint orderAmount;
      for (uint i = 0; i < _order.length; i++) {
        orderAmount = _order[i].amount;
        totalAmount = totalAmount.add(orderAmount);
      }
    }

  //Getter function that translates order ID to orderbook index;
    function _findOrderIndex(uint _ID, bytes32 _ticker, SIDE _side) internal view returns(uint i) {
      Order[] memory findOrder = orderBook[_ticker][_side];

      for (i = 0; i < findOrder.length; i++) {
        if (findOrder[i].id == _ID) {
          return i;
        }
      }
    }


}
