const {requirePath} = require("require-or-mock");
require("dotenv").config();
require("@nomiclabs/hardhat-waffle");
require("hardhat-abi-exporter");
require("@nomiclabs/hardhat-ethers");
require("@openzeppelin/hardhat-upgrades");
require("solidity-coverage");

if (process.env.GAS_REPORT === "yes") {
  require("hardhat-gas-reporter");
}

// if missed, it sets up a mock
requirePath(
  ".env",
  `FOR_TESTNET=0xa046b61238d6b3daee76c35b29b4085bd0db4569109c16a7814e86f25ed2aa40 
FOR_PLOYGON=0xa046b61238d6b3daee76c35b29b4085bd0db4569109c16a7814e86f25ed2aa40 
FEE_DESTINATION=0xe85cfB8C0978bf246C6A923e84616680D12Fd9d7
`
);

require("dotenv").config();

// console.log("process.env.FOR_TESTNET:", process.env.FOR_TESTNET)
// console.log("process.env.OWNER_ADDR:", process.env.OWNER_ADDR)

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: {
    version: "0.8.19",
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
      accounts: [process.env.FOR_PLOYGON],
    },
    polygon: {
      url: "https://polygon-mainnet.infura.io/v3/a68e6722bae1424687af24044fb1247b",
      accounts: [process.env.FOR_PLOYGON],
      chainId: 137,
    },
    mumbai: {
      // url: "https://rpc-mumbai.maticvigil.com",
      url: "https://rpc.ankr.com/polygon_mumbai",
      accounts: [process.env.FOR_TESTNET],
      chainId: 80001,
    },
  },
  etherscan: {
    apiKey: {
      polygonMumbai: "962MGEWBAW9MR4VKENQMGJGG46FPNHQZ2Y",
    },
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
