const DEX = artifacts.require("DEX");
const ETHWallet = artifacts.require("ETHWallet");
const LINK = artifacts.require("LINK");
const DEXGetters = artifacts.require("DEXGetters");

const truffleAssert = require('truffle-assertions');


contract.skip("DEX Wallet", accounts => {
  let linksymbol = web3.utils.keccak256("LINK");
  let ethsymbol = web3.utils.keccak256("ETH");
  let dex;
  let link;

  before(async () => {
    dex = await DEX.deployed();
    link = await LINK.deployed();

    await link.approve(dex.address, 20);
    await dex.addToken(linksymbol, link.address, {from: accounts[0]});
    await dex.deposit(20, linksymbol);
    await dex.depositETH({value: web3.utils.toWei('10', 'ether')});
  })

  it("should only be possible for owner to add tokens", async () => {

    await truffleAssert.passes(
      dex.addToken(linksymbol, link.address, {from: accounts[0]})
    )

    await truffleAssert.reverts(
    dex.addToken(linksymbol, link.address, {from: accounts[1]})
    )
  })

  it("Should handle deposits correctly", async () => {

    let linkBalance = await dex.balances(accounts[0], linksymbol);
    let ethBalance = await dex.balances(accounts[0], ethsymbol);

    await truffleAssert.passes(linkBalance == 10);
    await truffleAssert.passes(ethBalance == 10);
  })

  it("Should handle withdrawals correctly", async () => {

    let linkBalance0 = link.balanceOf(accounts[0]);
    let ethBalance0 = web3.eth.getBalance(accounts[0]);

    await dex.withdraw(20, linksymbol);
    await dex.withdraw(web3.utils.toWei('10'), ethsymbol);

    await truffleAssert.passes(link.balanceOf(accounts[0]) > linkBalance0);
    await truffleAssert.passes(web3.eth.getBalance(accounts[0]) > ethBalance0);
    await truffleAssert.passes(dex.balances(accounts[0], linksymbol) == 0);
    await truffleAssert.passes(dex.balances(accounts[0], ethsymbol) == 0);

  })
})

contract.skip("Limit Orders", accounts => {
    let linksymbol = web3.utils.keccak256("LINK");
    let ethsymbol = web3.utils.keccak256("ETH");
    let dex;
    let link;
    let buy = 0;
    let sell = 1;

    before(async () => {
      dex = await DEX.deployed();
      link = await LINK.deployed();

      await link.approve(dex.address, 20);
      await dex.addToken(linksymbol, link.address, {from: accounts[0]});
      await dex.deposit(20, linksymbol);
      await dex.depositETH({value: 10000});
    })

  it("Must have ETH deposited such that deposited eth >= buy order value", async () => {

    await dex.CreateLimitOrder(linksymbol, buy, 2, 300)

    let buyOrderPrice = await dex.getOrderPrice(linksymbol, buy, 0);

    await truffleAssert.passes(
          dex.balances(accounts[0], ethsymbol) >= buyOrderPrice)

    await truffleAssert.reverts(
      dex.CreateLimitOrder(linksymbol, buy, 5, 10000)
    )

    })

  it("Must have enough tokens deposited such that token balance >= sell order amount", async () => {

    await dex.CreateLimitOrder(linksymbol, sell, 2, 300)
    let sellOrderAmount = await dex.getOrderAmount(linksymbol, sell, 0);

    await console.log(dex.getOrderBook(linksymbol, sell))

    await truffleAssert.passes(
      dex.balances(accounts[0], linksymbol) >= sellOrderAmount)

    await truffleAssert.reverts(
      dex.CreateLimitOrder(linksymbol, sell, 500, 500)
    )

    })


  it("First order ([0]) in the BUY order book should have the highest price", async () => {

    await dex.CreateLimitOrder(linksymbol, buy, 2, 250)
    await dex.CreateLimitOrder(linksymbol, buy, 2, 340)
    await dex.CreateLimitOrder(linksymbol, buy, 2, 270)
    await dex.CreateLimitOrder(linksymbol, buy, 2, 425)
    await dex.CreateLimitOrder(linksymbol, buy, 2, 135)
    console.log(await dex.getOrderBook(linksymbol, buy))

    let orderBook = await dex.getOrderBook(linksymbol, buy);
    let order0 = await dex.getLimitPrice(linksymbol, buy, 0);

    for (i = orderBook.length - 1; i >= 1; i--) {
      await truffleAssert.passes( order0 >= orderBook[i] )
    }

})


  it("First order ([0]) in the SELL order book should have the lowest price", async () => {

    await dex.CreateLimitOrder(linksymbol, sell, 2, 400)
    await dex.CreateLimitOrder(linksymbol, sell, 2, 600)
    await dex.CreateLimitOrder(linksymbol, sell, 2, 350)
    await dex.CreateLimitOrder(linksymbol, sell, 2, 20000)
    console.log(await dex.getOrderBook(linksymbol, sell))


    let orderBook = dex.getOrderBook(linksymbol, 1);
    let order0 = dex.getLimitPrice(linksymbol, 1, 0);

    for (i = orderBook.length - 1; i >= 1; i--) {
      await truffleAssert.passes( order0 <= orderBook[i] )
    }
  })
})

contract("Market Orders", accounts => {
  let linksymbol = web3.utils.keccak256("LINK");
  let ethsymbol = web3.utils.keccak256("ETH");
  let dex;
  let link;
  let orderBookBuy;
  let orderBookSell;
  let orderBookBuyLength;
  let orderBookSellLength;
  let buy = 0;
  let sell = 1;
  let linkBalance0;
  let linkBalance1;
  let linkBalance2;
  let ethBalance0;
  let ethBalance1;
  let ethBalance2;

  before(async () => {
    dex = await DEX.deployed();
    link = await LINK.deployed();
    linkBalance0 = await dex.getBalance(linksymbol, {from: accounts[0]});
    linkBalance1 = await dex.getBalance(linksymbol, {from: accounts[1]});
    linkBalance2 = await dex.getBalance(linksymbol, {from: accounts[2]});
    ethBalance0 = await dex.getBalance(ethsymbol, {from:accounts[0]});
    ethBalance1 = await dex.getBalance(ethsymbol, {from:accounts[1]});
    ethBalance2 = await dex.getBalance(ethsymbol, {from:accounts[2]});
    orderBookSellLength = await dex.getOrderBookLength(linksymbol, sell);
    orderBookBuyLength = await dex.getOrderBookLength(linksymbol, buy);

    await link.approve(dex.address, 20);
    await dex.addToken(linksymbol, link.address, {from: accounts[0]});
    await dex.deposit(linksymbol, 20);
    await dex.depositETH({value: 10000, from: accounts[0]});
    await dex.depositETH({value: 1000, from: accounts[1]});
    await dex.depositETH({value: 1000, from: accounts[2]});

  })

//account[0]: 20 LINK, 10000 wei
//I don't like this one, I'm moving on--submitting market orders to an empty book reverts;
  it("Market orders will revert if the order book is empty", async () => {
console.log("BEGINNING TEST: Market orders will revert if the order book is empty")
    //These should revert if require check operates correctly;
console.log("Retrieving orderbooks")
    await truffleAssert.reverts(dex.getOrderBook(linksymbol, buy));
    await truffleAssert.reverts(dex.getOrderBook(linksymbol, sell));
console.log("Orderbooks empty")

    //These should revert if orderbook is empty;
console.log("Placing market buy and sell orders")
    await truffleAssert.reverts(dex.CreateMarketOrder(linksymbol, buy, 5));
    await truffleAssert.reverts(dex.CreateMarketOrder(linksymbol, sell, 5));
console.log("Orders reverted, orderbook empty")
  })


  it("Buyer must have enough ETH for market BUY orders", async () => {
console.log("BEGINNING TEST: Buyer must have enough ETH for market BUY orders")
    //Need to test getter function for market buy cost;
    //No orders on books, cost = 0;
    assert(await dex._marketBuyCost(linksymbol, 1) == 0, "_marketBuyCost error")
console.log("Market buy cost for empty orderbook:")
let marketBuyCost = await dex._marketBuyCost(linksymbol, 1)
console.log(marketBuyCost.toNumber())
    //Put order on book, test function's ability to count partial fills on one order;
console.log("Running tests for calculating market buy order prices")
console.log("New limit order: LINK, SELL, 3, 500, from account 0")
    await dex.CreateLimitOrder(linksymbol, sell, 3, 500, {from: accounts[0]});

console.log("Market buy cost for 1, 2, 3 LINK must equal 500, 1000, 1500 respectively")
console.log(await dex._marketBuyCost(linksymbol, 1),
            await dex._marketBuyCost(linksymbol, 2),
            await dex._marketBuyCost(linksymbol, 3))
    assert(await dex._marketBuyCost(linksymbol, 1) == 500, "_marketBuyCost error")
    assert(await dex._marketBuyCost(linksymbol, 2) == 1000, "_marketBuyCost error")
    assert(await dex._marketBuyCost(linksymbol, 3) == 1500, "_marketBuyCost error")

    //Put more orders on book, test function's ability to count multiple orders;
    await dex.CreateLimitOrder(linksymbol, sell, 1, 300, {from: accounts[0]});
    await dex.CreateLimitOrder(linksymbol, sell, 1, 400, {from: accounts[0]});

    assert(await dex._marketBuyCost(linksymbol, 4) == 1700, "_marketBuyCost error")
    assert(await dex._marketBuyCost(linksymbol, 5) == 2200, "_marketBuyCost error")

    //Put large order on book, test balance getter function and compare with marketBuyCost function;
console.log("New limit order: LINK, SELL, 10, 250, from account 0")
    await dex.CreateLimitOrder(linksymbol, sell, 10, 250, {from: accounts[0]});

console.log("Testing ETH balance and market buy cost comparisons")
console.log("getBalance(ETH) >= _marketBuyCost(LINK, 1)")
    await truffleAssert.passes(dex.getBalance(ethsymbol, {from: accounts[1]}) >= dex._marketBuyCost(linksymbol, 1));

console.log("getBalance(ETH) == 1000")
    await truffleAssert.passes(dex.balances(accounts[1], ethsymbol) == 1000, "balances error");
console.log("getBalance(ETH) <= _marketBuyCost(LINK, 10)")
    truffleAssert.passes(await dex.getBalance(ethsymbol, {from: accounts[1]}) <= dex._marketBuyCost(linksymbol, 10), "getBalance error");

  })

  it("Order removal must work", async () => {
console.log("BEGINNING TEST: Order removal must work")
console.log("New limit order: LINK, SELL, 1, 50, from account 0")
console.log("New limit order: LINK, BUY, 1, 50, from account 0")
    await dex.CreateLimitOrder(linksymbol, sell, 1, 50, {from: accounts[0]});
    await dex.CreateLimitOrder(linksymbol, buy, 1, 50, {from: accounts[0]});
console.log("Retrieving buy orderbook:")
console.log(await dex.getOrderBook(linksymbol, buy))
console.log("Retrieving sell orderbook:")
console.log(await dex.getOrderBook(linksymbol, sell))
console.log("Orderbook buy length: " + await dex.getOrderBookLength(linksymbol, buy))
console.log("Orderbook sell length: " + await dex.getOrderBookLength(linksymbol, sell))
    let orderBookBuyLength0 = await dex.getOrderBookLength(linksymbol, buy);
    let orderBookSellLength0 = await dex.getOrderBookLength(linksymbol, sell);

console.log("Removing sell order at index 0")
    let sellIndex0 = await dex.getOrderID(linksymbol, sell, 0)
    await truffleAssert.passes(dex.RemoveOrder(linksymbol, sell, sellIndex0.toNumber()))
console.log("Removing buy order at index 0")
    let buyIndex0 = await dex.getOrderID(linksymbol, buy, 0)
    await truffleAssert.passes(dex.RemoveOrder(linksymbol, buy, buyIndex0))

    console.log("Orderbook buy length: " + await dex.getOrderBookLength(linksymbol, buy))
    console.log("Orderbook sell length: " + await dex.getOrderBookLength(linksymbol, sell))
    let orderBookBuyLength1 = await dex.getOrderBookLength(linksymbol, buy);
    let orderBookSellLength1 = await dex.getOrderBookLength(linksymbol, sell);
    assert(orderBookSellLength0 > orderBookSellLength1, "Sell orderbook is not smaller after removal")
    assert(orderBookBuyLength0 > orderBookBuyLength1, "Buy orderbook is not smaller after removal")

  })

  it("When BUY market order is fulfilled, SELL order(s) must be removed and balances updated", async () => {
console.log("BEGINNING TEST: When BUY market order is fulfilled, SELL order(s) must be removed and balances updated")
console.log("LIMIT ORDER: LINK, SELL, 1, 100, FROM ACCOUNT 0")
    await dex.CreateLimitOrder(linksymbol, sell, 1, 100, {from: accounts[0]});
console.log("ORDERBOOK")
console.log(await dex.getOrderBook(linksymbol, sell))
console.log("MARKET ORDER: LINK, BUY, 12, FROM ACCOUNT 0")
    await dex.CreateMarketOrder(linksymbol, buy, 12, {from: accounts[0]})

ethBalance0 = await dex.getBalance(ethsymbol, {from: accounts[0]})
ethBalance1 = await dex.getBalance(ethsymbol, {from: accounts[1]})
linkBalance0 = await dex.getBalance(linksymbol, {from: accounts[0]})
linkBalance1 = await dex.getBalance(linksymbol, {from: accounts[1]})

    //Account 1 buys 1 LINK with market order, check that balances updated;
    assert(await dex.getBalance(linksymbol, {from: accounts[1]}) == 0)
console.log("Balances prior to market order:")
console.log("BALANCE: ACCOUNT 0, ETH - " + ethBalance0.toNumber())
console.log("BALANCE: ACCOUNT 0, LINK - " + linkBalance0.toNumber())
console.log("BALANCE: ACCOUNT 1, ETH - " + ethBalance1.toNumber())
console.log("BALANCE: ACCOUNT 1, LINK - " + linkBalance1.toNumber())

    await truffleAssert.passes(dex.getBalance(ethsymbol, {from: accounts[1]}) == 0)
console.log("MARKET ORDER: LINK, BUY, 2, FROM ACCOUNT 1")
    await dex.CreateMarketOrder(linksymbol, buy, 2, {from: accounts[1]})

    ethBalance0 = await dex.getBalance(ethsymbol, {from: accounts[0]})
    ethBalance1 = await dex.getBalance(ethsymbol, {from: accounts[1]})
    linkBalance0 = await dex.getBalance(linksymbol, {from: accounts[0]})
    linkBalance1 = await dex.getBalance(linksymbol, {from: accounts[1]})
    console.log("Balances after market order:")
    console.log("BALANCE: ACCOUNT 0, ETH - " + ethBalance0.toNumber())
    console.log("BALANCE: ACCOUNT 0, LINK - " + linkBalance0.toNumber())
    console.log("BALANCE: ACCOUNT 1, ETH - " + ethBalance1.toNumber())
    console.log("BALANCE: ACCOUNT 1, LINK - " + linkBalance1.toNumber())
    //console.log(await dex.getBalance(ethsymbol, {from: accounts[1]}))


    /*
    //assert(await dex.getBalance(linksymbol, {from: accounts[1]}) == 1)
    await truffleAssert.passes(dex.getBalance(ethsymbol, {from: accounts[1]}) == 900, "balance wrong")
    await truffleAssert.passes(dex.getBalance(linksymbol, {from: accounts[0]}) == 19)
    await truffleAssert.passes(dex.getBalance(ethsymbol, {from: accounts[0]}) == 10100)
    await truffleAssert.reverts(dex.getOrderBook(linksymbol, sell))
*/

    //assert(await dex.getOrderPrice(linksymbol, sell, 0) == 2250)

    //Account 0 places limit order, Account 1 buys order;
    //await dex.CreateLimitOrder(linksymbol, sell, 2, 100, {from: accounts[0]})
    //await dex.CreateMarketOrder(linksymbol, buy, 2, {from: accounts[1]})


  })


  it("Seller must have enough tokens for market SELL orders", async () => {
console.log("BEGINNING TEST: Seller must have enough tokens for market SELL orders")

linkBalance0 = await dex.getBalance(linksymbol, {from: accounts[0]})
linkBalance1 = await dex.getBalance(linksymbol, {from: accounts[1]})

console.log("Account 0 LINK balance: " + linkBalance0.toNumber())
console.log("Account 1 LINK balance: " + linkBalance1.toNumber())

console.log("Creating limit order: LINK, BUY, 1, 100, from account 1")
    await dex.CreateLimitOrder(linksymbol, buy, 1, 100, {from: accounts[1]});
console.log("Orderbook:")
console.log(await dex.getOrderBook(linksymbol, buy))

console.log("Creating market order: LINK, SELL, 1, from account 0")
    await truffleAssert.passes(dex.CreateMarketOrder(linksymbol, sell, 1, {from: accounts[0]}))
console.log("Creating market order: LINK, SELL, 10, from account 1")
    await truffleAssert.reverts(dex.CreateMarketOrder(linksymbol, sell, 10, {from: accounts[1]}))
  })

  it("When SELL market order is fulfilled, BUY order(s) must be removed and balances updated", async () => {
console.log("BEGINNING TEST: When SELL market order is fulfilled, BUY order(s) must be removed and balances updated")

linkBalance0 = await dex.getBalance(linksymbol, {from: accounts[0]})
linkBalance1 = await dex.getBalance(linksymbol, {from: accounts[1]})
linkBalance2 = await dex.getBalance(linksymbol, {from: accounts[2]})


console.log("Account 0 LINK balance:")
console.log(linkBalance0.toNumber())
console.log("Account 1 LINK balance:")
console.log(linkBalance1.toNumber())
console.log("Account 2 LINK balance:")
console.log(linkBalance2.toNumber())

console.log("Buy orderbook is empty")
//console.log(await dex.getOrderBook(linksymbol, buy))

console.log("LIMIT ORDER: LINK, BUY, 2 100, FROM ACCOUNT 2")
    await dex.CreateLimitOrder(linksymbol, buy, 2, 100, {from: accounts[2]});

console.log("MARKET ORDER: LINK, SELL, 1, FROM ACCOUNT 1")
    await dex.CreateMarketOrder(linksymbol, sell, 1, {from: accounts[1]})

console.log("MARKET ORDER: LINK, SELL, 1, FROM ACCOUNT 0")
    await dex.CreateMarketOrder(linksymbol, sell, 1, {from: accounts[0]})
    await truffleAssert.passes(dex.getOrderBook(linksymbol, buy).length == 0)

    linkBalance0 = await dex.getBalance(linksymbol, {from: accounts[0]})
    linkBalance1 = await dex.getBalance(linksymbol, {from: accounts[1]})
    linkBalance2 = await dex.getBalance(linksymbol, {from: accounts[2]})

console.log("Account 0 LINK balance:")
console.log(linkBalance0.toNumber())
console.log("Account 1 LINK balance:")
console.log(linkBalance1.toNumber())
console.log("Account 2 LINK balance:")
console.log(linkBalance2.toNumber())

    await truffleAssert.passes(dex.getBalance(linksymbol, {from: accounts[2]}) >= 2)


  })


  it("Market orders should be filled until order book is empty or market order is filled", async () => {
console.log("BEGINNING TEST: Market orders should be filled until order book is empty or market order is filled")
//console.log("Buy orderbook:")
//console.log(await dex.getOrderBook(linksymbol, buy))
//console.log("Sell orderbook:")
//console.log(await dex.getOrderBook(linksymbol, sell))
console.log("Creating limit order: LINK, BUY, 13, 15, from account 0")
await truffleAssert.passes(dex.CreateLimitOrder(linksymbol, buy, 3, 15, {from: accounts[0]}))
console.log("Creating limit order: LINK, SELL, 7, 20, from account 0")
await truffleAssert.passes(dex.CreateLimitOrder(linksymbol, sell, 7, 20, {from: accounts[0]}))


console.log("Creating market order: LINK, SELL, 15, from account 0")
    await truffleAssert.passes(dex.CreateMarketOrder(linksymbol, sell, 15, {from: accounts[0]}))
console.log("Creating market order: LINK, BUY, 10, from account 0")
    await truffleAssert.passes(dex.CreateMarketOrder(linksymbol, buy, 10, {from: accounts[0]}))
console.log("Buy orderbook length = " + await dex.getOrderBookLength(linksymbol, buy))
    await truffleAssert.passes(dex.getOrderBookLength(linksymbol, buy) == 0)
    console.log("Sell orderbook length = " + await dex.getOrderBookLength(linksymbol, sell))
    await truffleAssert.passes(dex.getOrderBookLength(linksymbol, sell) == 0)

  })

  it.skip("ETH balance of buyer should decrease by filled amount", async () => {
    await dex.createLimitOrder(1, linksymbol, 4, 50)

    let ethBalanceInit = await dex.getBalance(ethsymbol);
    let buyOrderInit = await getOrderPrice(linksymbol, 1, 0);

    await dex.createMarketOrder(linksymbol, 0, 2);

    let buyOrderEnd = await getOrderPrice(linksymbol, 1, 0);
    let filledAmount = buyOrderInit - buyOrderEnd;

    assert(ethBalanceInit - dex.getBalance(ethsymbol) == filledAmount);

  })


  it.skip("Token balances of sellers should decrease by filled amount", async () => {
    await dex.createLimitOrder(0, linksymbol, 4, 50)

    let ethBalanceInit = await dex.getBalance(ethsymbol);
    let buyOrderInit = await getOrderPrice(linksymbol, 1, 0);

    await dex.createMarketOrder(linksymbol, 0, 2);

    let buyOrderEnd = await getOrderPrice(linksymbol, 1, 0);
    let filledAmount = buyOrderInit - buyOrderEnd;

    assert(ethBalanceInit - dex.getBalance(ethsymbol) == filledAmount);

  })


  it.skip("FIlled limit orders should be removed from orderbook", async () => {
    await dex.createLimitOrder(0, linksymbol, 3, 100)
    await dex.createLimitOrder(1, linksymbol, 3, 100)

    let sellOrderID = orderBookSell[0].id;
    let buyOrderID = orderBookBuy[0].id;

    await dex.createMarketOrder(linksymbol, 1, 3);
    assert(orderBookBuy[0].id != buyOrderID);

    await dex.createMarketOrder(linksymbol, 0, 3);
    assert(orderBookSell[0].id != sellOrderID);

  })

  it.skip("Partially filled limit orders should be modified to represent remaining amount", async () => {
    await dex.createLimitOrder(0, linksymbol, 3, 100)
    await dex.createLimitOrder(1, linksymbol, 3, 100)
    let buyOrderAmount = orderBookBuy[0].amount;
    let sellOrderAmount = orderBookSell[0].amount;

    let filled = 1;

    await dex.createMarketOrder(linksymbol, 1, filled);
    await dex.createMarketOrder(linksymbol, 0, filled);

    assert(buyOrderAmount - filled == orderBookBuy[0].amount)
    assert(sellOrderAmount - filled == orderBookSell[0].amount)

  })
})
