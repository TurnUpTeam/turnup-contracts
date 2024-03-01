const {ethers, upgrades} = require("hardhat");
const web3 = require("web3");

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);
  console.log("balance:", await ethers.provider.getBalance(deployer.address));
  console.log("getGasPrice:", await ethers.provider.getGasPrice());
  console.log("getFeeData:", await ethers.provider.getFeeData());

  let lfgAddress = "0x2aA9B551929d55fa8ecf6e3b009E13bde9E79bA8";  // test mumbai
  
  const factory = await ethers.getContractFactory("LFGAirdropV1"); 
  let airdrop = await upgrades.deployProxy(factory); 
  console.debug("Tx:", airdrop.deployTransaction.hash);
  await airdrop.deployed();
  console.debug("Deployed at", airdrop.address);
  
  let tx = await airdrop.setLfgToken(lfgAddress);
  await tx.wait();

  tx = await airdrop.setFundDestination(deployer.address);
  await tx.wait();
  
  tx = await airdrop.setMaxLfgPerMember(ethers.utils.parseEther("10000"));
  await tx.wait();

  console.log("LFG address:", await airdrop.lfg());
  console.log("fundDestination:", await airdrop.fundDestination());
  console.log("maxLfgPerMember:", await airdrop.maxLfgPerMember());
  console.log("dropMemberAmount:", await airdrop.dropMemberAmount());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
