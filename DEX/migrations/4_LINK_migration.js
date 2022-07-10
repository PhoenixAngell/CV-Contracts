const LINK = artifacts.require("LINK");
const DEX = artifacts.require("DEX");
const DEXGetters = artifacts.require("DEXGetters");


module.exports = async function (deployer, network, accounts) {
  await deployer.deploy(LINK);
  let link = await LINK.deployed();
  let dex = await DEX.deployed();
  let linkticker = "LINK";
  let ethticker = "ETH";
  let buy = 0;
  let sell = 1;

  await link.approve(dex.address, 100);
  await dex.addToken(linkticker, link.address);
  await dex.deposit(linkticker, 100);

  await dex.depositETH({value: 2500, from: accounts[0]});
  await dex.depositETH({value: 1000, from: accounts[1]});

console.log("CREATING LIMIT ORDER: LINK, BUY, 1, 300")
  await dex.CreateLimitOrder(linkticker, buy, 1, 300)
console.log("CREATING LIMIT ORDER: LINK, BUY, 2, 200")
  await dex.CreateLimitOrder(linkticker, buy, 2, 200)
console.log("CREATING LIMIT ORDER: LINK, BUY, 3, 100")
  await dex.CreateLimitOrder(linkticker, buy, 3, 100)

console.log("CREATING LIMIT ORDER: LINK, SELL, 4, 170")
  await dex.CreateLimitOrder(linkticker, sell, 4, 170)
console.log("CREATING LIMIT ORDER: LINK, SELL, 1, 300")
  await dex.CreateLimitOrder(linkticker, sell, 1, 300)
console.log("CREATING LIMIT ORDER: LINK, SELL, 2, 250")
  await dex.CreateLimitOrder(linkticker, sell, 2, 250)

console.log("SELL ORDERBOOK LENGTH = " + await dex.getOrderBookLength(linkticker, sell))
console.log("BUY ORDERBOOK LENGTH = " + await dex.getOrderBookLength(linkticker, buy))

console.log("BUY ORDERBOOK:")
console.log(await dex.getOrderBook(linkticker, buy))
console.log("SELL ORDERBOOK:")
console.log(await dex.getOrderBook(linkticker, sell))

console.log("CREATING MARKET ORDER: LINK, BUY, 5")
  await dex.CreateMarketOrder(linkticker, buy, 5)
console.log("CREATING MARKET ORDER: LINK, SELL, 4")
  await dex.CreateMarketOrder(linkticker, sell, 4)

console.log("SELL ORDERBOOK LENGTH = " + await dex.getOrderBookLength(linkticker, sell))
console.log("BUY ORDERBOOK LENGTH = " + await dex.getOrderBookLength(linkticker, buy))

console.log("BUY ORDERBOOK:")
console.log(await dex.getOrderBook(linkticker, buy))
console.log("SELL ORDERBOOK:")
console.log(await dex.getOrderBook(linkticker, sell))

console.log("CREATING MARKET ORDER: LINK, SELL, 10")
  await dex.CreateMarketOrder(linkticker, sell, 10)
console.log("CREATING MARKET ORDER: LINK, BUY, 10")
  await dex.CreateMarketOrder(linkticker, buy, 10)

console.log("SELL ORDERBOOK LENGTH = " + await dex.getOrderBookLength(linkticker, sell))
console.log("BUY ORDERBOOK LENGTH = " + await dex.getOrderBookLength(linkticker, buy))


/*
  console.log("LIMIT BUY ORDER: 2 LINK, 35 WEI/LINK")
  await dex.CreateLimitOrder(linkticker, 0, 2, 35, {from: accounts[1]})
  console.log("LIMIT BUY ORDER: 2 LINK, 30 WEI/LINK")
  await dex.CreateLimitOrder(linkticker, 0, 2, 30, {from: accounts[1]})
  console.log("LIMIT BUY ORDER: 1 LINK, 25 WEI/LINK")
  await dex.CreateLimitOrder(linkticker, 0, 1, 30, {from: accounts[1]})
  console.log("LIMIT BUY ORDER: 1 LINK, 20 WEI/LINK")
  await dex.CreateLimitOrder(linkticker, 0, 1, 30, {from: accounts[1]})

  console.log("ORDERBOOK")
  console.log(await dex.getOrderBook(linkticker, 0))

console.log("ACCOUNTS0 ETH")
  console.log(await dex.getBalance(ethticker, {from: accounts[0]}))
console.log("ACCOUNTS0 LINK")
  console.log(await dex.getBalance(linkticker, {from: accounts[0]}))
console.log("ACCOUNTS1 ETH")
  console.log(await dex.getBalance(ethticker, {from: accounts[1]}))
console.log("ACCOUNTS1 LINK")
  console.log(await dex.getBalance(linkticker, {from: accounts[1]}))

console.log("MARKET SELL ORDER: 3 LINK")
  await dex.CreateMarketOrder(linkticker, 1, 3, {from: accounts[0]})
console.log("ORDERBOOK")
console.log(await dex.getOrderBook(linkticker, 0))

console.log("ACCOUNTS0 ETH")
  console.log(await dex.getBalance(ethticker, {from: accounts[0]}))
console.log("ACCOUNTS0 LINK")
  console.log(await dex.getBalance(linkticker, {from: accounts[0]}))
console.log("ACCOUNTS1 ETH")
  console.log(await dex.getBalance(ethticker, {from: accounts[1]}))
console.log("ACCOUNTS1 LINK")
  console.log(await dex.getBalance(linkticker, {from: accounts[1]}))

console.log("MARKET SELL ORDER: 6 LINK")
  await dex.CreateMarketOrder(linkticker, 1, 6, {from: accounts[0]})

console.log("ACCOUNTS0 ETH")
  console.log(await dex.getBalance(ethticker, {from: accounts[0]}))
console.log("ACCOUNTS0 LINK")
  console.log(await dex.getBalance(linkticker, {from: accounts[0]}))
console.log("ACCOUNTS1 ETH")
  console.log(await dex.getBalance(ethticker, {from: accounts[1]}))
console.log("ACCOUNTS1 LINK")
  console.log(await dex.getBalance(linkticker, {from: accounts[1]}))
console.log("CREATING LIMIT ORDER: LINK, BUY, 1, 100")
  await dex.CreateLimitOrder(linkticker, 0, 1, 100)
console.log("CREATING MARKET ORDER: LINK, SELL, 1")
  await dex.CreateMarketOrder(linkticker, 1, 1)
console.log("ORDERBOOK BUY LENGTH = " + await dex.getOrderBookLength(linkticker, 1))
*/

};
