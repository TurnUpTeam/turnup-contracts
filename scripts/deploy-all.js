const path = require("path");
const hre = require("hardhat");
const {ethers} = require("hardhat");
let deployUtils;

async function main() {
  require("./consoleLogAlert")();

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
    console.debug("Deployed at", deployed.address);
    return deployed;
  }

  // This assumes that you have an .env file like the example in template.env
  // You can call this file like, for example:
  //
  //     bin/deploy.sh all mumbai

  const {
    TOKEN_HOLDER,
    FIRST_VALIDATOR,
    FIRST_OPERATOR,
    MAX_LOCK_TIME,
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
  let maxLockTime = parseInt(MAX_LOCK_TIME) * 24 * 3600;

  const lfg = await deployProxy(
    "LFGToken",
    TOKEN_HOLDER,
    maxSupply,
    initialSupply,
    amountReservedToPool,
    amountReservedToSharesPool
  );

  // deploy factory

  let maxDaily = ethers.utils.parseEther(MAX_DAILY);
  const factory = await deployProxy("LFGFactory", lfg.address, [FIRST_VALIDATOR], maxDaily, MIN_FACTORY_LOCK_TIME);

  await factory.setOperator(FIRST_OPERATOR, true);

  await lfg.setFactory(factory.address);

  // deploy pool

  const blockNumber = await ethers.provider.getBlockNumber();

  // those are values for Polygon
  // they must be adapted for other chains
  const blocksPerWeek = 42000 * 7;
  const threeYearsBlocks = 42000 * 365 * 3;

  const reservedToPool = BigInt(amountReservedToPool.toString());
  const tokenPerBlock = (reservedToPool * 489n) / (BigInt(Math.floor(threeYearsBlocks)) * 100n);

  const weight = 200;

  // 16 weeks
  const minLockTime = 3600 * 24 * 7 * 16;

  const pool = await deployProxy(
    "CorePool",
    lfg.address,
    tokenPerBlock,
    blocksPerWeek,
    blockNumber + 2,
    blockNumber + threeYearsBlocks,
    weight,
    minLockTime,
    factory.address
  );

  await lfg.setPool(pool.address);
  await factory.setPool(pool.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
