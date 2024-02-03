const {expect} = require("chai");
const EthDeployUtils = require("eth-deploy-utils");

const deployUtils = new EthDeployUtils();

const {getTimestamp, increaseBlockTimestampBy, getBlockNumber, cl} = require("./helpers");
const {ethers} = require("hardhat");
const {max} = require("hardhat/internal/util/bigint");

describe("CorePool", function () {
  let factory;
  let lfg;
  let pool;
  let owner,
    operator,
    validator,
    tokenHolder,
    bob,
    alice,
    fred,
    jim,
    red,
    lee,
    jane,
    pippo,
    john,
    valery,
    august,
    marcel,
    gael,
    frankie,
    robert,
    will;
  let tokenPerBlock;

  function bn(v) {
    return ethers.utils.parseEther(v.toString());
  }

  const week = 3600 * 24 * 7;
  const blocksPerDay = 42000;
  const reservedToTool = 400000000;
  let amountReservedToPool = bn(reservedToTool.toString());
  const minLockTime = 3600 * 24 * 7 * 16;

  before(async function () {
    [
      owner,
      operator,
      validator,
      tokenHolder,
      bob,
      alice,
      fred,
      jim,
      red,
      lee,
      jane,
      pippo,
      john,
      valery,
      august,
      marcel,
      gael,
      frankie,
      robert,
      will,
    ] = await ethers.getSigners();
  });

  it.only("should fix the pool", async function () {
    let maxSupply = bn("3000000000");
    let initialSupply = bn("900000000");
    let amountReservedToSharesPool = bn("200000000");
    let amountReservedToPool = bn("400000000");

    lfg = await deployUtils.deployProxy(
      "LFGToken",
      tokenHolder.address,
      maxSupply,
      initialSupply,
      amountReservedToPool,
      amountReservedToSharesPool
    );

    // this may be too little in production:
    const maxDaily = (await lfg.amountReservedToPool()).div(365);

    factory = await deployUtils.deployProxy("LFGFactory", lfg.address, [validator.address], maxDaily, 3600 * 12);

    await lfg.setFactory(factory.address);

    const blockNumber = await getBlockNumber();

    pool = await deployUtils.deployProxy(
      "CorePool",
      lfg.address,
      blockNumber + 2,
      minLockTime,
      amountReservedToPool,
      factory.address
    );

    await lfg.setPool(pool.address);
    await factory.setPool(pool.address);

    expect(await lfg.pool()).to.equal(pool.address);
    expect(await factory.pool()).to.equal(pool.address);

    expect(await lfg.balanceOf(pool.address)).to.equal(amountReservedToPool);

    // FIX

    let newPool = await deployUtils.deployProxy(
      "CorePool",
      lfg.address,
      blockNumber + 5,
      minLockTime,
      amountReservedToPool,
      factory.address,
      {gasLimit: 20000000}
    );

    await pool.transferBalance(newPool.address, lfg.address);
    expect(await lfg.balanceOf(newPool.address)).to.equal(amountReservedToPool);

    await factory.fixPool(newPool.address);
    expect(await factory.pool()).to.equal(newPool.address);
    await lfg.fixPool(newPool.address);
    expect(await lfg.pool()).to.equal(newPool.address);
  });
});
