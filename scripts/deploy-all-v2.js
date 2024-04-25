
const {ethers, upgrades} = require("hardhat");

async function sleep(ms) {
  await new Promise((r) => setTimeout(r, ms)); 
}

async function getGasPrice() {
  let gasPrice = await ethers.provider.getGasPrice()
  return gasPrice.mul(150).div(100)
}

async function deployProxy(contractName, ...args) {
  let options;
  if (typeof args[args.length - 1] === "object") {
    if (args[args.length - 1].hasOwnProperty("gasLimit") || args[args.length - 1].hasOwnProperty("gasPrice")) {
      options = args.pop();
    }
  }
  console.debug("Deploying", contractName, "to", hre.network.name);
  const contract = await ethers.getContractFactory(contractName);
  const deployed = await upgrades.deployProxy(contract, [...args], options);
  console.debug("Tx:", deployed.deployTransaction.hash);
  await deployed.deployed();

  sleep(1500)
  
  console.debug("Proxy address", deployed.address);
  console.debug("Implementation address",  await upgrades.erc1967.getImplementationAddress(deployed.address));
  console.debug("Admin address", await upgrades.erc1967.getAdminAddress(deployed.address));
  
  // await run("verify:verify", {address: deployed.address})

  return deployed;
}

async function deployTurnupShares() {
  let turnup = await deployProxy("TurnupSharesV4")
  await turnup.setFeeDestination(process.env.FEE_DESTINATION, {gasPrice: await getGasPrice()})
  let feePercent = ethers.utils.parseEther("0.05")
  await turnup.setProtocolFeePercent(feePercent, {gasPrice: await getGasPrice()})
  await turnup.setSubjectFeePercent(feePercent, {gasPrice: await getGasPrice()})
  await turnup.setOperator(process.env.FIRST_OPERATOR, true, {gasPrice: await getGasPrice()}) 

  // sleep(3 * 1000)
  // console.log("protocolFeeDestination:", await turnup.protocolFeeDestination())
  // console.log("protocolFeePercent:", await turnup.protocolFeePercent())
  // console.log("subjectFeePercent:", await turnup.subjectFeePercent())
  // console.log("operator address:", await turnup.operator())

  return turnup
}

async function deployLFGToken() {
  const {
    TOKEN_HOLDER,
    FIRST_VALIDATOR,
    FIRST_OPERATOR, 
    MAX_SUPPLY,
    INITIAL_SUPPLY,
    AMOUNT_RESERVED_TO_POLL,
    AMOUNT_RESERVED_TO_SHARES_POLL,
    MAX_DAILY,
    MIN_FACTORY_LOCK_TIME,
  } = process.env;

  if (!/^0x[0-9a-fA-F]{40}$/.test(FIRST_VALIDATOR)) {
    throw new Error(`Invalid VALIDATOR_TURNUP: ${FIRST_VALIDATOR}`);
  }

  if (!/^0x[0-9a-fA-F]{40}$/.test(TOKEN_HOLDER)) {
    throw new Error(`Invalid TOKEN_HOLDER: ${TOKEN_HOLDER}`);
  }

  let maxSupply = ethers.utils.parseEther(MAX_SUPPLY);
  let initialSupply = ethers.utils.parseEther(INITIAL_SUPPLY);
  let amountReservedToPool = ethers.utils.parseEther(AMOUNT_RESERVED_TO_POLL);
  let amountReservedToSharesPool = ethers.utils.parseEther(AMOUNT_RESERVED_TO_SHARES_POLL); 

  // deploy token

  const lfgToken = await deployProxy("LFGToken", TOKEN_HOLDER, maxSupply, initialSupply, amountReservedToPool, amountReservedToSharesPool);

  // deploy factory

  let maxDaily = ethers.utils.parseEther(MAX_DAILY);
  const lfgFactory = await deployProxy("LFGFactory", lfgToken.address, [FIRST_VALIDATOR], maxDaily, MIN_FACTORY_LOCK_TIME);
  await lfgFactory.setOperator(FIRST_OPERATOR, true, {gasPrice: await getGasPrice()});

  await lfgToken.setFactory(lfgFactory.address, {gasPrice: await getGasPrice()});

  // deploy core pool
  
  const blockNumber = await ethers.provider.getBlockNumber();
  
  // 16 weeks
  const minLockTime = 3600 * 24 * 7 * 16;

  const pool = await deployProxy("CorePool", 
    lfgToken.address, 
    blockNumber + 150,
    // ^ we let the pool start in 150 blocks (~5 minutes) to have time to announce it
    // Feel free to change this parameter.
    minLockTime,
    amountReservedToPool,
    lfgFactory.address
  );

  await lfgToken.setPool(pool.address, {gasPrice: await getGasPrice()});
  await lfgFactory.setPool(pool.address, {gasPrice: await getGasPrice()});

  return [lfgToken, lfgFactory, pool]
} 

async function deployPFPAuction(lfgAddress) {
  let auction = await deployProxy("PFPAuction", lfgAddress)
  return auction
}

async function deployTurnUPNFT(nftName, symbol, tokenUri) {
  let nft = await deployProxy("TurnUPNFT", nftName, symbol, tokenUri)
  return nft
}

async function deployLottery(lfgAddress, sharesAddress) {
  const {
    LOTTERY_MIN_LFG_PER_PICK,
    LOTTERY_MIN_MATIC_PER_PICK,
    LOTTERY_RED_PACK_LIFE_TIME,
    LOTTERY_MAX_START_TIME,
    LOTTERY_PROTOCOL_FEE_PERCENT,
    LOTTERY_PROTOCOL_FEE_DESTINATION,
  } = process.env;
 
  let minLfgPerPick = ethers.utils.parseEther(LOTTERY_MIN_LFG_PER_PICK);
  let minMaticPerPick = ethers.utils.parseEther(LOTTERY_MIN_MATIC_PER_PICK);
  let protocolFeePercent = ethers.utils.parseEther(LOTTERY_PROTOCOL_FEE_PERCENT);

  let lottery = await deployProxy("Lottery", minLfgPerPick, minMaticPerPick, 
    LOTTERY_RED_PACK_LIFE_TIME, LOTTERY_MAX_START_TIME, protocolFeePercent, LOTTERY_PROTOCOL_FEE_DESTINATION)
 
  await lottery.setLFGToken(lfgAddress, {gasPrice: await getGasPrice()});
  await lottery.setShares(sharesAddress, {gasPrice: await getGasPrice()});
  
  return lottery
}

async function deployMemeFactory() {
  let memeFactory = await deployProxy("MemeFactory", [])
  return memeFactory 
}

async function main() { 
  console.log("start...")

  /*
  let turnup = await deployTurnupShares()

  let lfgContracts = await deployLFGToken()
  let lfgToken = lfgContracts[0]
  let lfgFactory = lfgContracts[1]
  let corePool = lfgContracts[2]

  let auction = await deployPFPAuction(lfgToken.address)

  let nftName = "Test name"
  let symbol = "Test symbol"
  let tokenUri = "https://dev.badass.xyz/nftjosn_test/"
  let nft = await deployTurnUPNFT(nftName, symbol, tokenUri)

  let lottery = await deployLottery(lfgToken.address, turnup.address)

  console.log("TurnupShares address:", turnup.address)
  console.log("LFGToken address:", lfgToken.address)
  console.log("LFGFactory address:", lfgFactory.address)
  console.log("CorePool address:", corePool.address)
  console.log("Lottery address:", lottery.address)
  console.log("PFPAuction address:", auction.address)
  console.log("TurnUPNFT address:", nft.address) 
  */

  let memeFactory = await deployMemeFactory()
  console.log("MemeFactory address:", memeFactory.address)

  console.log("end...")
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
