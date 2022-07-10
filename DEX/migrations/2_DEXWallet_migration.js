const DEXWallet = artifacts.require("DEXWallet");
const DEX = artifacts.require("DEX");

module.exports = async function (deployer, network, accounts) {
  await deployer.deploy(DEXWallet);

};
