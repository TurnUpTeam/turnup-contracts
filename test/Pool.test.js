const {expect} = require("chai");
const EthDeployUtils = require("eth-deploy-utils");

const deployUtils = new EthDeployUtils();

const {
  signPackedData,
  privateKeyByWallet,
  getTimestamp,
  addr0,
  increaseBlockTimestampBy,
  getBlockNumber,
} = require("./helpers");
const {ethers} = require("hardhat");

describe("LFGFactory", function () {
  let factory;
  let lfg;
  let pool;
  let owner, bob, alice, fred, operator, validator, tokenHolder;

  const blocksPerWeek = 42000 * 7;
  const threeYearsBlocks = 42000 * 365 * 3;

  before(async function () {
    [owner, bob, alice, fred, operator, validator, tokenHolder] = await ethers.getSigners();
  });

  async function initAndDeploy() {
    let maxSupply = ethers.utils.parseEther("3000000000");
    let initialSupply = ethers.utils.parseEther("900000000");
    let amountReservedToPool = ethers.utils.parseEther("300000000");
    let amountReservedToSharesPool = ethers.utils.parseEther("200000000");
    let maxLockTime = 365 * 24 * 3600;
    lfg = await deployUtils.deployProxy(
      "LFGToken",
      tokenHolder.address,
      maxSupply,
      initialSupply,
      amountReservedToPool,
      amountReservedToSharesPool,
      maxLockTime
    );

    const maxDaily = (await lfg.amountReservedToPool()).div(365);

    factory = await deployUtils.deployProxy("LFGFactory", lfg.address, [validator.address], maxDaily);

    await factory.setOperator(operator.address, true);

    await lfg.setFactory(factory.address);

    const blockNumber = await getBlockNumber();

    const reserved = (await lfg.amountReservedToPool()).div("1000000000000000000").toNumber();

    const reservedToPool = BigInt((await lfg.amountReservedToPool()).toString());

    const tokenPerBlock = (reservedToPool * 489n) / (BigInt(Math.floor(threeYearsBlocks)) * 100n);

    function validateInitialAmountPerBlock(reservedAmount, initialAmount, blocksPerPeriod, decayPeriods, decayFactor = 97n) {
      let startAmount = initialAmount;
      for (let i = 0; i < decayPeriods; i++) {
        reservedAmount -= initialAmount * blocksPerPeriod;
        initialAmount = (initialAmount * decayFactor) / 100n;
      }
      expect(reservedAmount > 0n).to.be.true;
      expect(initialAmount < startAmount / 10n).to.be.true;
    }

    validateInitialAmountPerBlock(
      BigInt((await lfg.amountReservedToPool()).toString()),
      BigInt(tokenPerBlock.toString()),
      BigInt(blocksPerWeek),
      104n,
      97n
    );

    // on Polygon there are ~42000 blocks per day

    const weight = 200;
    // 16 weeks
    const minLockTime = 3600 * 24 * 7 * 16;

    pool = await deployUtils.deployProxy(
      "CorePool",
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

  async function getSignature(hash, signer) {
    const privateKey = privateKeyByWallet[signer.address];
    return signPackedData(hash, privateKey);
  }

  beforeEach(async function () {
    await initAndDeploy();
  });

  it("should let bob stake some LFG and get rewards after 10 days", async function () {
    await lfg.connect(tokenHolder).transfer(bob.address, ethers.utils.parseEther("1000"));
    await lfg.connect(bob).approve(pool.address, ethers.utils.parseEther("1000"));

    let ts = await getTimestamp();

    await pool.connect(bob).stake(ethers.utils.parseEther("500"), ts + 3600 * 24 * 7 * 20);
    await increaseBlockTimestampBy(3600 * 24 * 10);

    let bobBalanceBefore = await lfg.balanceOf(bob.address);
    let pendingYieldingRewards = await pool.pendingYieldRewards(bob.address);
    expect(pendingYieldingRewards).to.be.equal("31898238747549531165");

    await pool.connect(bob).processRewards();

    let bobBalanceAfter = await lfg.balanceOf(bob.address);
    expect(bobBalanceAfter.sub(bobBalanceBefore).sub(pendingYieldingRewards).gt(0)).to.be.true;
  });

  it("should let bob, alice and fred stake some LFG and get rewards", async function () {
    await lfg.connect(tokenHolder).transfer(bob.address, ethers.utils.parseEther("1000"));
    await lfg.connect(bob).approve(pool.address, ethers.utils.parseEther("1000"));
    await lfg.connect(tokenHolder).transfer(alice.address, ethers.utils.parseEther("1000"));
    await lfg.connect(alice).approve(pool.address, ethers.utils.parseEther("1000"));
    await lfg.connect(tokenHolder).transfer(fred.address, ethers.utils.parseEther("1000"));
    await lfg.connect(fred).approve(pool.address, ethers.utils.parseEther("1000"));

    let ts = await getTimestamp();

    await pool.connect(bob).stake(ethers.utils.parseEther("500"), ts + 1 + 3600 * 24 * 7 * 16);
    await pool.connect(alice).stake(ethers.utils.parseEther("500"), ts + 3600 * 24 * 365);
    await pool.connect(fred).stake(ethers.utils.parseEther("500"), ts + 3600 * 24 * 180);
    await increaseBlockTimestampBy(3600 * 24 * 10);

    let bobBalanceBefore = await lfg.balanceOf(bob.address);
    let pendingYieldingRewards = await pool.pendingYieldRewards(bob.address);
    expect(pendingYieldingRewards).to.be.equal("53188880282720078855");
    pendingYieldingRewards = await pool.pendingYieldRewards(alice.address);
    expect(pendingYieldingRewards).to.be.equal("32583153661745023335");
    pendingYieldingRewards = await pool.pendingYieldRewards(fred.address);
    expect(pendingYieldingRewards).to.be.equal("9922682298180907750");

    await pool.connect(bob).processRewards();

    let bobBalanceAfter = await lfg.balanceOf(bob.address);
    expect(bobBalanceAfter.sub(bobBalanceBefore).sub(pendingYieldingRewards).gt(0)).to.be.true;
  });
});
