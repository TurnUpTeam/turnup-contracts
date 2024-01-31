const {ethers, upgrades} = require("hardhat");
const web3 = require("web3");

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);

  console.log("balance:", await ethers.provider.getBalance(deployer.address));

  console.log("getGasPrice:", await ethers.provider.getGasPrice());
  console.log("getFeeData:", await ethers.provider.getFeeData());

  const factory = await ethers.getContractFactory("TurnupSharesV4");

  // const turnup = await upgrades.deployProxy(factory, { kind: "transparent", redeployImplementation: "always", "timeout": 180000})
  const turnup = await upgrades.deployProxy(factory, {
    kind: "transparent",
    redeployImplementation: "onchange",
    timeout: 180000,
  });
  await turnup.deployed();

  console.log("Turnup(Proxy) address:", await turnup.address);
  console.log("Turnup(Implementation) address:", await upgrades.erc1967.getImplementationAddress(turnup.address));
  console.log("Turnup(Admin) address:", await upgrades.erc1967.getAdminAddress(turnup.address));

  // console.log("process.env.FEE_DESTINATION:", process.env.FEE_DESTINATION)
  await new Promise((r) => setTimeout(r, 15000));
  await turnup.setFeeDestination(process.env.FEE_DESTINATION);

  percent = web3.utils.toWei("0.05", "ether");

  await new Promise((r) => setTimeout(r, 15000));
  await turnup.setProtocolFeePercent(percent);

  await new Promise((r) => setTimeout(r, 15000));
  await turnup.setSubjectFeePercent(percent);

  await new Promise((r) => setTimeout(r, 15000));
  await turnup.setOperator(process.env.FIRST_OPERATOR, true);

  await new Promise((r) => setTimeout(r, 15000));

  console.log("fee destination:", await turnup.protocolFeeDestination());
  console.log("Protocol fee percent", await turnup.protocolFeePercent());
  console.log("Subject fee percent", await turnup.subjectFeePercent());
  console.log("operator", await turnup.operator());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
