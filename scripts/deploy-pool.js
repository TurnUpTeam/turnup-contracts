const path = require("path");

const DeployUtils = require("eth-deploy-utils");
const {ethers} = require("hardhat");
let deployUtils;

async function main() {
  deployUtils = new DeployUtils(path.resolve(__dirname, ".."), console.log);
  require("./consoleLogAlert")();

  const [deployer] = await ethers.getSigners();

  const lfg = await deployUtils.attach("LFGToken");

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
