const hre = require("hardhat");

const implName = "PFPAuction";
const proxyAddress = "0x1d43aE42a2801854aED722009780832e773C6632"; // publish, pfpauction

async function main() {
  console.log("proxy address", proxyAddress);
  console.log("deploy implementation", implName);

  const factory = await ethers.getContractFactory(implName);
  await upgrades.validateUpgrade(proxyAddress, factory);

  const impl = await hre.ethers.deployContract(implName);
  console.log("wait tx:", impl.deployTransaction.hash);
  await impl.deployed();

  console.log("Implementation address:", impl.address);

  console.log("Implementation verify...");
  await run("verify:verify", {address: impl.address});
  console.log("Implementation verify,address:", impl.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
