const {requirePath} = require("require-or-mock");
require("dotenv").config();
require("@nomiclabs/hardhat-waffle");
require("hardhat-abi-exporter");
require("@nomiclabs/hardhat-ethers");
require("@openzeppelin/hardhat-upgrades");
require("solidity-coverage");
require("hardhat-contract-sizer");

if (process.env.GAS_REPORT === "yes") {
  require("hardhat-gas-reporter");
}

// if missed, it sets up a mock
requirePath(
  ".env",
  `FOR_TESTNET=0xa046b61238d6b3daee76c35b29b4085bd0db4569109c16a7814e86f25ed2aa40 
  FOR_POLYGON=0xa046b61238d6b3daee76c35b29b4085bd0db4569109c16a7814e86f25ed2aa40 
  FEE_DESTINATION=0xe85cfB8C0978bf246C6A923e84616680D12Fd9d7
  INFURA_KEY=hshahsagdgashdgdhas
  POLYGON_SCAN_API=ewiuryweiurwyriwyriw
`
);

require("dotenv").config();

// console.log("process.env.FOR_TESTNET:", process.env.FOR_TESTNET)
// console.log("process.env.OWNER_ADDR:", process.env.OWNER_ADDR)

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.20",
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  networks: {
    hardhat: {
      blockGasLimit: 10000000,
    },
    localhost: {
      url: "http://127.0.0.1:8545",
      chainId: 1337,
    },
    bsc: {
      url: "https://bsc-dataseed.binance.org",
      chainId: 56,
      gasPrice: 20000000000,
      accounts: [process.env.FOR_POLYGON],
    },
    polygon: {
      url: "https://polygon-mainnet.infura.io/v3/" + process.env.INFURA_KEY,
      accounts: [process.env.FOR_POLYGON],
      chainId: 137,
      gasPrice: 200000000000,
    },
    amoy: {
      url: "https://polygon-amoy.infura.io/v3/d8a840b52ce24a7da3550a33036cb126", // + process.env.INFURA_KEY,
      accounts: [process.env.FOR_TESTNET],
      chainId: 80002,
    },
  },
  etherscan: {
    apiKey: {
      polygonMumbai: process.env.POLYGON_SCAN_API,
      polygon: process.env.POLYGON_SCAN_API,
      amoy: process.env.POLYGON_SCAN_API,
    },
    customChains: [
      {
        network: "amoy",
        chainId: 80002,
        urls: {
          apiURL: "https://api-amoy.polygonscan.com/api",
          browserURL: "https://amoy.polygonscan.com/",
        },
      },
    ],
  },
  sourcify: {
    enabled: false,
  },
  gasReporter: {
    enabled: true,
    currency: "USD",
  },
  abiExporter: [
    {
      path: "./abi",
      format: "json",
    },
  ],
};
