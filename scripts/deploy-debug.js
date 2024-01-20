const path = require("path");

const DeployUtils = require("eth-deploy-utils");
const {ethers} = require("hardhat");
let deployUtils;

async function main() {
  deployUtils = new DeployUtils(path.resolve(__dirname, ".."), console.log);
  require("./consoleLogAlert")();

  const [deployer] = await ethers.getSigners();

  // This assumes that you have an .env file like the example in template.env
  // You can call this file like, for example:
  //
  //     bin/deploy.sh all mumbai

  let TOKEN_HOLDER = deployer.address,
    FIRST_VALIDATOR = deployer.address,
    FIRST_OPERATOR = deployer.address,
    MAX_LOCK_TIME = "365",
    MAX_SUPPLY = "2500000000",
    INITIAL_SUPPLY = "1000000000",
    AMOUNT_RESERVED_TO_POLL = "300000000",
    MAX_DAILY = "100000";

  let maxSupply = ethers.utils.parseEther(MAX_SUPPLY);
  let initialSupply = ethers.utils.parseEther(INITIAL_SUPPLY);
  let amountReservedToPool = ethers.utils.parseEther(AMOUNT_RESERVED_TO_POLL);
  let maxLockTime = parseInt(MAX_LOCK_TIME) * 24 * 3600;

  const lfg = await deployUtils.deployProxy(
    "LFGToken",
    TOKEN_HOLDER,
    maxSupply,
    initialSupply,
    amountReservedToPool,
    maxLockTime
  );

  const debugAddr1 = "0xC1b11DdF0CDAFD387c1511197562653dc208D07f";
  const debugAddr2 = "0x8A96e7F2cae379559496C810e9B7DecE971B771E";
  const debugAddr3 = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8";

  // deployer is the token holder
  await deployUtils.Tx(lfg.transfer(debugAddr1, ethers.utils.parseEther("100000")));
  await deployUtils.Tx(lfg.transfer(debugAddr2, ethers.utils.parseEther("100000")));
  await deployUtils.Tx(lfg.transfer(debugAddr3, ethers.utils.parseEther("100000")));

  let maxDaily = ethers.utils.parseEther(MAX_DAILY);
  const factory = await deployUtils.deployProxy("LFGFactory", lfg.address, [FIRST_VALIDATOR], maxDaily);

  await factory.setOperator(FIRST_OPERATOR, true);

  await lfg.setFactory(factory.address);

  // const lfg = await deployUtils.attach("LFGToken");

  const blockNumber = await ethers.provider.getBlockNumber();

  // those are values for Polygon
  // they must be adapted for other chains
  const blocksPerWeek = 42000 * 7;
  const threeYearsBlocks = 42000 * 365 * 3;

  const reservedToPool = BigInt((await lfg.amountReservedToPool()).toString());
  const tokenPerBlock = (reservedToPool * 489n) / (BigInt(Math.floor(threeYearsBlocks)) * 100n);

  const weight = 200;
  // 16 weeks
  const minLockTime = 3600 * 24 * 7 * 16;

  const pool = await deployUtils.deployProxy(
    "Pool",
    lfg.address,
    tokenPerBlock,
    blocksPerWeek,
    blockNumber + 2,
    blockNumber + threeYearsBlocks,
    weight,
    minLockTime
  );

  await lfg.setPool(pool.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
