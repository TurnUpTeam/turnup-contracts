// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
require("dotenv").config();
const hre = require("hardhat");

const ethers = hre.ethers;
const DeployUtils = require("./lib/DeployUtils");
let deployUtils;

async function main() {
  deployUtils = new DeployUtils(ethers);
  const chainId = await deployUtils.currentChainId();

  const contractName = process.env.CONTRACT;
  const contractAddress = process.env.CONTRACT_ADDRESS;
  const contractFolder = process.env.CONTRACT_FOLDER || "";
  const contract = await deployUtils.getContract(contractName, contractFolder, contractAddress, chainId);
  await upgrades.forceImport(contractAddress, contract, {kind: "uups"});
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
