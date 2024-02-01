const hre = require("hardhat");

async function main() {
  const impl = await hre.ethers.deployContract("TurnupSharesV3Pausable");
  console.log("Turnup(Implementation) deploy...")
  await impl.deployed();
  console.log("Turnup(Implementation) address:", impl.address)
 
  console.log("Turnup(Implementation) verify...")
  await run("verify:verify", {address:impl.address})
  console.log("Turnup(Implementation) verify,address:", impl.address)
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
