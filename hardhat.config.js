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
  BASE_SEPOLIA_UNISWAP_V3=0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24
  BASE_SEPOLIA_UNISWAP_POSITION_MANAGER=0x27F971cb582BF9E50F397e4d29a5C7A34f11faA2
  BASE_SEPOLIA_WTH=0x4200000000000000000000000000000000000006
  BASE_UNISWAP_V3=0x33128a8fC17869897dcE68Ed026d694621f6FDfD
  BASE_UNISWAP_POSITION_MANAGER=0x03a520b32C04BF3bEEf7BEb72E919cf822Ed34f1
  BASE_WTH=0x4200000000000000000000000000000000000006
  POLYGON_UNISWAP_V3=0x1F98431c8aD98523631AE4a59f267346ea31F984
  POLYGON_UNISWAP_POSITION_MANAGER=0xC36442b4a4522E871399CD717aBDD847Ab11FE88
  POLYGON_WTH=0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270
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
      gasPrice: 150000000000,
      accounts: [process.env.FOR_POLYGON],
    },
    polygon: {
      url: "https://polygon-mainnet.infura.io/v3/" + process.env.INFURA_KEY,
      accounts: [process.env.FOR_POLYGON],
      chainId: 137,
      gasPrice: 80000000000,
    },
    amoy: {
      url: "https://polygon-amoy.infura.io/v3/d8a840b52ce24a7da3550a33036cb126", // + process.env.INFURA_KEY,
      accounts: [process.env.FOR_TESTNET],
      chainId: 80002,
    },
    base: {
      url: "https://base-mainnet.g.alchemy.com/v2/" + process.env.ALCHEMY_BASE_KEY,
      accounts: [process.env.FOR_TESTNET],
      chainId: 8453,
    },
    sepolia: {
      url: "https://base-sepolia.g.alchemy.com/v2/" + process.env.ALCHEMY_BASE_SEPOLIA_KEY,
      accounts: [process.env.FOR_TESTNET],
      chainId: 84532,
    },
  },
  etherscan: {
    apiKey: {
      polygon: process.env.POLYGON_SCAN_API,
      amoy: process.env.POLYGON_SCAN_API,
      base: process.env.BASE_SCAN_API,
      sepolia: process.env.BASE_SCAN_API,
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
      {
        network: "base",
        chainId: 8453,
        urls: {
          apiURL: "https://api.basescan.org/api",
          browserURL: "https://basescan.org"
        }
      },
      {
        network: "sepolia",
        chainId: 84532,
        urls: {
          apiURL: "https://api-sepolia.basescan.org/api",
          browserURL: "https://sepolia.basescan.org/"
        }
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
