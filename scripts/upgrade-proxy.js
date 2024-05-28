const {ethers, upgrades, network} = require("hardhat");
const web3 = require("web3");

// let proxyAddress = "0x5eA29B2680D01C28BC2C3d18d12D34F761153b09"; // amoy
let proxyAddress = "0x5AAdF8a148CfA8320a2b4cc654973958E204d677"; // base sepolia
let contractName = "MemeFactory";

async function main() {
  console.log("upgrade contract,network:", network.name, ",chainId:", network.config.chainId);
  console.log("contract name:", contractName);
  console.log("proxy address:", proxyAddress);

  const [deployer] = await ethers.getSigners();

  const factory = await ethers.getContractFactory(contractName);
  await upgrades.validateUpgrade(proxyAddress, factory);
  const p = await upgrades.upgradeProxy(proxyAddress, factory, {
    timeout: 300000,
    redeployImplementation: "always",
  });

  console.log("Proxy address:", await p.address);
  console.log("Implementation address:", await upgrades.erc1967.getImplementationAddress(p.address));
  console.log("Admin address:", await upgrades.erc1967.getAdminAddress(p.address));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
