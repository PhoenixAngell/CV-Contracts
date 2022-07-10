const LINK = artifacts.require("LINK");
const DEX = artifacts.require("DEX");
const DEXGetters = artifacts.require("DEXGetters");

module.exports = async function (deployer, network, accounts) {
  await deployer.deploy(DEXGetters);

};
