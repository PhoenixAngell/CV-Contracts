pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "./DEXWallet.sol";
import "./DEXGetters.sol";
import "./OpenZeppelinDependencies/SafeMath.sol";

contract DEX is DEXWallet {
  using SafeMath for uint256;

  function CreateLimitOrder(string memory ticker_, SIDE _side, uint _amount, uint _price) external {
    bytes32 _ticker = _keccak256(ticker_);
    if (_side == SIDE.SELL){
      require(balances[msg.sender][_ticker] >= _amount, "Insufficient tokens");
    }
    else if (_side == SIDE.BUY){
      require(balances[msg.sender][ETH] >= _amount.mul(_price), "Insufficient ETH");
    }
      _newLimitOrder(_ticker, _side, _amount, _price);
  }

  function _newLimitOrder(bytes32 _ticker, SIDE _side, uint _amount, uint _price) internal {
    Order memory newOrder = Order(orderID, msg.sender, _side, _ticker, _amount, _price);
    orderBook[_ticker][_side].push(newOrder);
    orderID++;
    _orderRemoved = false;
    _sort(_ticker, _side, _orderRemoved);
  }

  function CreateMarketOrder(string memory ticker_, SIDE _side, uint256 _amount) external {
    bytes32 _ticker = _keccak256(ticker_);
    SIDE limitSide;

    if (_side == SIDE.SELL){
      require(balances[msg.sender][_ticker] >= _amount, "Insufficient token balance");
      require(orderBook[_ticker][SIDE.BUY].length > 0, "No orders exist");
      limitSide = SIDE.BUY;
    }
    if (_side == SIDE.BUY){
      require(balances[msg.sender][ETH] >= _marketBuyCost(ticker_, _amount), "Insufficient ETH");
      require(orderBook[_ticker][SIDE.SELL].length > 0, "No orders exist");
      limitSide = SIDE.SELL;
    }

    _fillOrder(_ticker, limitSide, _amount);

  }

  function _fillOrder(bytes32 _ticker, SIDE limitSide, uint _amount) internal {
    uint orderRemaining = _amount;
    address seller;
    address buyer;
    uint i;

    Order[] storage _order = orderBook[_ticker][limitSide];

    //Set buyers and sellers;
    if (limitSide == SIDE.BUY){
      seller = msg.sender;
      buyer = _order[i].trader;
    }
    else {
      seller = _order[i].trader;
      buyer = msg.sender;
    }

    //Fill order loop;
    for (i = 0; i < _order.length && orderRemaining > 0; i++) {
      uint limitAmount = _order[i].amount;

      //orderRemaining < limitAmount
      if (orderRemaining < limitAmount && orderRemaining > 0) {
        uint limitPrice = _order[i].price;
        uint remainingPrice = orderRemaining.mul(limitPrice);
        _trade(_ticker, seller, buyer, remainingPrice, orderRemaining);
        _order[i].amount = limitAmount.sub(orderRemaining);
        orderRemaining = 0;
        break;
      }

      //orderRemaining >= limitAmount
      if (orderRemaining >= limitAmount && limitAmount > 0) {

        uint limitPrice = _order[i].price;
        uint orderPrice = limitAmount.mul(limitPrice);
        _trade(_ticker, seller, buyer, orderPrice, limitAmount);
        orderRemaining = orderRemaining.sub(limitAmount);
        _order[i].amount = 0;

        //if last order on orderbook, then break;
        if (i == _order.length - 1) {
          break;
        }
      }
    }

/*
    for (i = _order.length - 1; i > 0; i--) {
      if (_order[i].amount == 0) {
        _removeOrder(_ticker, limitSide, i);
      }
      if (i == 1) {
        _removeOrder(_ticker, limitSide, 0);
      }
    }
*/
    //Cleanup loop, purges filled limit orders;
    for (i = _order.length; i > 0; i--) {
      if (_order[i - 1].amount == 0) {
        _removeOrder(_ticker, limitSide, i - 1);
        /*if (i == 1) {
            break;
        }*/
      }
    }
  }



  function _trade(bytes32 _ticker, address _seller, address _buyer, uint _price, uint _amount) internal {
    balances[_seller][ETH] = balances[_seller][ETH].add(_price);
    balances[_seller][_ticker] = balances[_seller][_ticker].sub(_amount);
    balances[_buyer][ETH] = balances[_buyer][ETH].sub(_price);
    balances[_buyer][_ticker] = balances[_buyer][_ticker].add(_amount);
  }

  function RemoveOrder(string memory ticker_, SIDE _side, uint _ID) external {
    bytes32 _ticker = _keccak256(ticker_);
    Order[] memory removedOrder = orderBook[_ticker][_side];
    uint _index = _findOrderIndex(_ID, _ticker, _side);

    require(removedOrder[_index].trader == msg.sender, "Only trader can remove");
    _removeOrder(_ticker, _side, _index);
  }

  function _removeOrder(bytes32 _ticker, SIDE _side, uint _index) internal {
    Order[] storage _orderBook = orderBook[_ticker][_side];

    if (_index < _orderBook.length - 1){
      Order memory newEntry = _orderBook[_orderBook.length - 1];
      _orderBook[_index] = newEntry;
      _orderBook.pop();
      _orderRemoved = true;
      _sort(_ticker, _side, _orderRemoved);
    }

    else if (_index == _orderBook.length - 1) {
      _orderBook.pop();
    }
  }

  function _sort(bytes32 _ticker, SIDE _side, bool _orderRemoved) internal {
    Order[] storage ORDER = orderBook[_ticker][_side];
    uint ORDERLength = ORDER.length - 1;

    if (_orderRemoved == true){
      if (_side == SIDE.BUY) {
        for (uint i = 0; i < ORDERLength; i += 1) {
          if (ORDER[i].price < ORDER[i + 1].price) {
            _swapOrders( _ticker, _side, i, _orderRemoved);
          }
        }
      }
      if (_side == SIDE.SELL) {
        for (uint i = 0; i < ORDERLength; i += 1) {
          if (ORDER[i].price > ORDER[i + 1].price) {
            _swapOrders(_ticker, _side, i, _orderRemoved);
          }
        }
      }
    }

    else if (_orderRemoved == false){
      if (_side == SIDE.BUY) {
        for (uint i = ORDERLength; i >= 1; i--) {
          if (ORDER[i].price > ORDER[i - 1].price) {
            _swapOrders(_ticker, _side, i, _orderRemoved);
          }
        }
      }
      else if (_side == SIDE.SELL) {
        for (uint i = ORDERLength; i >= 1; i--) {
          if (ORDER[i].price < ORDER[i - 1].price) {
            _swapOrders(_ticker, _side, i, _orderRemoved);
          }
          else break;
          }
        }
      }
    }

  function _swapOrders(bytes32 _ticker, SIDE _side, uint _index, bool _orderRemoved) internal {
    uint nextIndex;
    if (_orderRemoved == false){
      nextIndex = _index - 1;
    }
    else {
      nextIndex = _index + 1;
    }
    Order[] storage ORDER = orderBook[_ticker][_side];
    Order memory newOrder = ORDER[_index];
    Order memory oldOrder = ORDER[nextIndex];
    ORDER[nextIndex] = newOrder;
    ORDER[_index] = oldOrder;
  }
}
