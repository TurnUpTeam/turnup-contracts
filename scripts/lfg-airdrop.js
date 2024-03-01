const {ethers} = require("hardhat");
const fs = require("fs");

const dropUsersFile = "./scripts/lfg_airdrop_users.csv";
const dropUserAmountPer = 2;

const lfgAirdropAddress = "0x5B78eb1C51F5580034ec8B6A39e59b81Fb67d371";   // test, mumbai 

const gasPrice = ethers.utils.parseUnits("80", "gwei");

async function main() {
  console.log("Airdrop users file:", dropUsersFile);
  console.log("Airdrop user amount per:", dropUserAmountPer);

  const [deployer] = await ethers.getSigners();
  console.log("Airdop account:", deployer.address);

  const factory = await ethers.getContractFactory("LFGAirdropV1");
  const airdrop = factory.attach(lfgAirdropAddress);
  
  console.log("LFG token contract address:", await airdrop.lfg());
  console.log("fundDestination:", await airdrop.fundDestination());
  console.log("maxLfgPerMember:", await airdrop.maxLfgPerMember());
  console.log("dropMemberAmount:", await airdrop.dropMemberAmount());
  
  let allUsers = new Array();
  let eligibleUsers = new Array();

  const content = fs.readFileSync(dropUsersFile, "utf-8");
  content.split(/\r?\n/).forEach(line => {
    let toks = line.trim().split(" ");
    allUsers.push({"wallet": toks[0], "amount": toks[1]});
  });
  console.log("$LFG airdrop user count:", allUsers.length);
  
  let idx = 0;
  while (idx < allUsers.length) {
    let batchUsers = new Array();
    let batchSize = Math.min(dropUserAmountPer, allUsers.length - idx);
    for (var i = 0; i < batchSize; i++) {
      batchUsers.push(allUsers[idx + i]["wallet"]);
    }
    
    let retVal = await airdrop.batchGetAirdropAmount(batchUsers);
    for (var i = 0; i < retVal.length; i++) {
      if (retVal[i].isZero()) {
        eligibleUsers.push(allUsers[idx + i]);
      }
    }

    idx += batchSize;
  }
  
  console.log("$LFG airdrop eligible user count:", eligibleUsers.length);

  idx = 0;
  while (idx < eligibleUsers.length) {
    let batchUsers = new Array();
    let batchAmount = new Array();
    let batchSize = Math.min(dropUserAmountPer, eligibleUsers.length - idx);
    for (var i = 0; i < batchSize; i++) {
      batchUsers.push(eligibleUsers[idx + i]["wallet"]);
      batchAmount.push(ethers.utils.parseEther(eligibleUsers[idx + i]["amount"]));
    }

    let tx = await airdrop.airdrop(batchUsers, batchAmount, {gasPrice: gasPrice});
    await tx.wait();

    idx += batchSize;

    console.log("Airdrop,eligibleUsers count:", eligibleUsers.length, ",idx:", idx);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
