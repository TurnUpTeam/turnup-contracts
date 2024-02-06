const {ethers, upgrades} = require("hardhat");
const web3 = require("web3");

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);
  console.log("balance:", await ethers.provider.getBalance(deployer.address));
  console.log("getGasPrice:", await ethers.provider.getGasPrice());
  console.log("getFeeData:", await ethers.provider.getFeeData());

  const {
    LOTTERY_MIN_LFG_PER_PICK,
    LOTTERY_MIN_MATIC_PER_PICK,
    LOTTERY_RED_PACK_LIFE_TIME,
    LOTTERY_PROTOCOL_FEE_PERCENT,
    LOTTERY_PROTOCOL_FEE_DESTINATION,
  } = process.env;


  let lfgAddress = "";
  let sharesAddress = "";

  let minLfgPerPick = ethers.utils.parseEther(LOTTERY_MIN_LFG_PER_PICK);
  let minMaticPerPick = ethers.utils.parseEther(LOTTERY_MIN_MATIC_PER_PICK);
  let protocolFeePercent = ethers.utils.parseEther(LOTTERY_PROTOCOL_FEE_PERCENT);

  const factory = await ethers.getContractFactory("Lottery");
  const lottery = await upgrades.deployProxy(
    factory, 
    minLfgPerPick,
    minMaticPerPick,
    LOTTERY_RED_PACK_LIFE_TIME,
    protocolFeePercent,
    LOTTERY_PROTOCOL_FEE_DESTINATION,
    {
      kind: "transparent",
      redeployImplementation: "always", 
      timeout: 180000,
    }
  );
  await turnup.deployed();

  console.log("Lottery(Proxy) address:", await turnup.address);
  console.log("Lottery(Implementation) address:", await upgrades.erc1967.getImplementationAddress(turnup.address));
  console.log("Lottery(Admin) address:", await upgrades.erc1967.getAdminAddress(turnup.address));

  await lottery.setLFGToken(lfgAddress);
  await lottery.setShares(sharesAddress);
    
  console.log("minLfgPerPick:", await lottery.minLfgPerPick());
  console.log("minMaticPerPick:", await lottery.minMaticPerPick());
  console.log("redPackLifeTime:", await lottery.redPackLifeTime());
  console.log("protocolFeePercent:", await lottery.protocolFeePercent());
  console.log("protocolFeeDestination:", await lottery.protocolFeeDestination());
  console.log("lfgProtocolFees:", await lottery.lfgProtocolFees());
  console.log("maticProtocolFees:", await lottery.maticProtocolFees());
  console.log("lfg:", await lottery.lfg());
  console.log("shares:", await lottery.shares()); 
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
