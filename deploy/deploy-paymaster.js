const { utils, Wallet } = require('zksync-ethers')
const { Deployer } = require('@matterlabs/hardhat-zksync')
const { HardhatRuntimeEnvironment } = require('hardhat/types')
// const* as ethers from "ethers";
// import { HardhatRuntimeEnvironment } from "hardhat/types";


module.exports = async function (hre) {

  let wallet = await hre.zksyncEthers.getWallet(0)
  let deployer = new Deployer(hre, wallet)

  let contract = await deployer.loadArtifact('MomentPayMaster')
  let pm = await hre.zkUpgrades.deployProxy(wallet, contract)

  console.log(`Moment pay mastger deployed tx at: ${pm.deployTransaction.hash}`)
  await pm.waitForDeployment()
  let addr = await pm.getAddress()
  console.log('Moment pay master deployed to:', addr)
}
