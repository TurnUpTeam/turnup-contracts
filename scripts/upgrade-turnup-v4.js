const {ethers, upgrades} = require("hardhat");
const web3 = require("web3");

async function main() {
  const [deployer] = await ethers.getSigners();

  console.log("Upgrading Turnup with the account:", deployer.address);

  const implementation = await ethers.getContractFactory("TurnupSharesV4");

  const turnup = await upgrades.upgradeProxy("0x5a1B8f5780b41bE5ACB7BD423E2676526685Ef64", implementation);
  console.log("Box upgraded");

  console.log("Turnup(Proxy) address:", await turnup.address);
  console.log("Turnup(Implementation) address:", await upgrades.erc1967.getImplementationAddress(turnup.address));
  console.log("Turnup(Admin) address:", await upgrades.erc1967.getAdminAddress(turnup.address));

  await new Promise((r) => setTimeout(r, 5000));

  console.log("fee destination:", await turnup.protocolFeeDestination());
  console.log("Protocol fee percent", await turnup.protocolFeePercent());
  console.log("Subject fee percent", await turnup.subjectFeePercent());
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
