const { utils, Wallet } = require('zksync-ethers')
const { Deployer } = require('@matterlabs/hardhat-zksync')
const { HardhatRuntimeEnvironment } = require('hardhat/types')
// const* as ethers from "ethers";
// import { HardhatRuntimeEnvironment } from "hardhat/types";


module.exports = async function (hre) {
  const {
    FIRST_VALIDATOR,
    ABSTRACT_TESTNET_UNISWAP_V3,
    ABSTRACT_TESTNET_UNISWAP_POSITION_MANAGER,
    ABSTRACT_TESTNET_WETH,
  } = process.env

  console.log(`validator ${FIRST_VALIDATOR}`) 
  console.log(`ABSTRACT_TESTNET_WETH ${ABSTRACT_TESTNET_WETH}`)
  console.log(`ABSTRACT_TESTNET_UNISWAP_V3 ${ABSTRACT_TESTNET_UNISWAP_V3}`)
  console.log(`ABSTRACT_TESTNET_UNISWAP_POSITION_MANAGER ${ABSTRACT_TESTNET_UNISWAP_POSITION_MANAGER}`)

  let wallet = await hre.zksyncEthers.getWallet(0)
  let deployer = new Deployer(hre, wallet)
  
  let contract = await deployer.loadArtifact('MomentFactory')
  let factory = await hre.zkUpgrades.deployProxy(wallet, contract, [
    [FIRST_VALIDATOR,], 
    ABSTRACT_TESTNET_UNISWAP_V3,
    ABSTRACT_TESTNET_UNISWAP_POSITION_MANAGER,
    ABSTRACT_TESTNET_WETH,
  ])
  console.log(`Moment factory deployed tx at: ${factory.deployTransaction.hash}`)
  await factory.waitForDeployment()
  let factoryAddr = await factory.getAddress()
  console.log('Moment factory deployed to:', factoryAddr)

  contract = await deployer.loadArtifact('MomentToken')
  let tokens = await hre.zkUpgrades.deployProxy(wallet, contract, [factoryAddr])
  console.log(`Moment Token deployed tx at: ${tokens.deployTransaction.hash}`)
  await tokens.waitForDeployment()
  let tokensAddr = await tokens.getAddress()
  console.log('Moment Token deployed to:', tokensAddr)

  factory.connect(wallet)
  console.log(factory)
  let tx = await factory.setMomentToken(tokensAddr)
  console.log(tx)
}

