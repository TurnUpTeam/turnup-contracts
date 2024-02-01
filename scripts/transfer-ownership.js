const { ethers, upgrades } = require("hardhat");
const web3 = require("web3")
 
async function main() {   
  // const gnosisSafe = '0x0155D07A8597F52d807f4663821cc36f0f34A710';      // polygon mumbai
  const gnosisSafe = '0x756A2859f7712aF94dC8F0a6845734B7a03aF95D';      // polygon mainnet
  // const gnosisSafe = '0x99f117069F9ED15476003502AD8D96107A180648';   // bsc testnet
  // const gnosisSafe = '0xfDB8f807773a2435E2De0c834f68c42bB6a36aE9';      // bsc mainnet
  
  console.log("Transferring ownership of ProxyAdmin...");

  // The owner of the ProxyAdmin can upgrade our contracts
  await upgrades.admin.transferProxyAdminOwnership(gnosisSafe);
  console.log("Transferred ownership of ProxyAdmin to:", gnosisSafe);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
