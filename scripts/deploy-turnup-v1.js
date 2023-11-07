const {ethers, upgrades} = require("hardhat");
const web3 = require("web3");

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);

  const TurnupSharesV1 = await ethers.getContractFactory("TurnupSharesV1");
  const turnup = await upgrades.deployProxy(TurnupSharesV1, {kind: "uups"});
  await turnup.deployed();

  console.log("Turnup(Proxy) address:", await turnup.address);
  console.log("Turnup(Implementation) address:", await upgrades.erc1967.getImplementationAddress(turnup.address));
  console.log("Turnup(Admin) address:", await upgrades.erc1967.getAdminAddress(turnup.address));

  console.log("process.env.FEE_DESTINATION:", process.env.FEE_DESTINATION);
  await turnup.setFeeDestination(process.env.FEE_DESTINATION);

  percent = web3.utils.toWei("0.05", "ether");

  await new Promise((r) => setTimeout(r, 3000));
  await turnup.setProtocolFeePercent(percent);

  await new Promise((r) => setTimeout(r, 3000));
  await turnup.setSubjectFeePercent(percent);

  await new Promise((r) => setTimeout(r, 5000));

  console.log("fee destination:", await turnup.protocolFeeDestination());
  console.log("Protocol fee percent", await turnup.protocolFeePercent());
  console.log("Subject fee percent", await turnup.subjectFeePercent());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
