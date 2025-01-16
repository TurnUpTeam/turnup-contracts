const {requirePath} = require("require-or-mock");
require("dotenv").config();
// require("@nomiclabs/hardhat-waffle");
require("hardhat-abi-exporter");
// require("@nomiclabs/hardhat-ethers");
// require("@openzeppelin/hardhat-upgrades");
// require("solidity-coverage");
// require("hardhat-contract-sizer");
require("@matterlabs/hardhat-zksync")
require('@matterlabs/hardhat-zksync-verify')

// if (process.env.GAS_REPORT === "yes") {
//   require("hardhat-gas-reporter");
// }

// if missed, it sets up a mock
requirePath(
  ".env",
  `FOR_TESTNET=0xa046b61238d6b3daee76c35b29b4085bd0db4569109c16a7814e86f25ed2aa40 
  FOR_POLYGON=0xa046b61238d6b3daee76c35b29b4085bd0db4569109c16a7814e86f25ed2aa40 
  FEE_DESTINATION=0xe85cfB8C0978bf246C6A923e84616680D12Fd9d7
  INFURA_KEY=hshahsagdgashdgdhas
  POLYGON_SCAN_API=ewiuryweiurwyriwyriw
  BASE_SEPOLIA_UNISWAP_V3=0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24
  BASE_SEPOLIA_UNISWAP_POSITION_MANAGER=0x27F971cb582BF9E50F397e4d29a5C7A34f11faA2
  BASE_SEPOLIA_WTH=0x4200000000000000000000000000000000000006
  BASE_UNISWAP_V3=0x33128a8fC17869897dcE68Ed026d694621f6FDfD
  BASE_UNISWAP_POSITION_MANAGER=0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1
  BASE_WTH=0x4200000000000000000000000000000000000006
  POLYGON_UNISWAP_V3=0x1F98431c8aD98523631AE4a59f267346ea31F984
  POLYGON_UNISWAP_POSITION_MANAGER=0xC36442b4a4522E871399CD717aBDD847Ab11FE88
  POLYGON_WTH=0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270
  ABSTRACT_TESTNET_UNISWAP_V3=0xac5cCDcefb1EB9276Aa6141bd828081aFC0D23A4
  ABSTRACT_TESTNET_UNISWAP_POSITION_MANAGER=0x4ED897F89Dd4D4893Bd1053c699afFe01ca0f893
  ABSTRACT_TESTNET_WETH=0x740810c5CB6a562BC0F4F387dC7cFaDa9f3A7ebf
`
);

require("dotenv").config();

// console.log("process.env.FOR_TESTNET:", process.env.FOR_TESTNET)
// console.log("process.env.OWNER_ADDR:", process.env.OWNER_ADDR)

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  zksolc: {
    version: "latest",
    settings: {
      enableEraVMExtensions: true,
    },
  },
  solidity: {
    version: "0.8.20",
  },
  defaultNetwork: 'abstractTestnet',
  networks: {
    hardhat: {
      // blockGasLimit: 10000000,
      zksync: false,
    },
    abstractTestnet: {
      url: 'https://api.testnet.abs.xyz',
      accounts: [process.env.FOR_TESTNET],
      chainId: 11124,
      zksync: true,
      ethNetwork: 'sepolia',
      verifyURL: 'https://api-explorer-verify.testnet.abs.xyz/contract_verification',
    },
  },
  abiExporter: [
    {
      path: "./abi",
      format: "json",
    },
  ],
};
