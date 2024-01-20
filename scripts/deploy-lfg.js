const path = require("path");

const DeployUtils = require("eth-deploy-utils");
const {ethers} = require("hardhat");
let deployUtils;

async function main() {
  deployUtils = new DeployUtils(path.resolve(__dirname, ".."), console.log);
  require("./consoleLogAlert")();

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

  const lfg = await deployUtils.deployProxy(
    "LFGToken",
    TOKEN_HOLDER,
    maxSupply,
    initialSupply,
    amountReservedToPool,
    amountReservedToSharesPool,
    maxLockTime
  );

  let maxDaily = ethers.utils.parseEther(MAX_DAILY);
  const factory = await deployUtils.deployProxy("LFGFactory", lfg.address, [FIRST_VALIDATOR], maxDaily);

  await factory.setOperator(FIRST_OPERATOR, true);

  await lfg.setFactory(factory.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
