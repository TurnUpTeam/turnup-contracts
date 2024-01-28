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
  mineBlocks,
  cl,
} = require("./helpers");
const {ethers} = require("hardhat");

describe.only("CorePool", function () {
  let factory;
  let lfg;
  let pool;
  let owner, operator, validator, tokenHolder, bob, alice, fred, jim, red, lee, jane;
  let tokenPerBlock;

  const blocksPerDay = 42000;
  const blocksPerWeek = blocksPerDay * 7;
  const twoYearsBlocks = blocksPerDay * 365 * 2;
  const amountReservedToPool = ethers.utils.parseEther("400000000");

  before(async function () {
    [owner, operator, validator, tokenHolder, bob, alice, fred, jim, red, lee, jane] = await ethers.getSigners();
  });

  async function initAndDeploy() {
    let maxSupply = ethers.utils.parseEther("3000000000");
    let initialSupply = ethers.utils.parseEther("900000000");
    let amountReservedToSharesPool = ethers.utils.parseEther("200000000");

    // pool configuration
    tokenPerBlock = 42530984996738421395n;
    // ^ calculated using scripts/calculate-tokenPerBlock.js for a 2 years pool with 97% decay factor
    // and a reserved amount of 400M tokens.

    console.log(tokenPerBlock / 1000000000000000000n);

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

    await factory.setOperator(operator.address, true);

    await lfg.setFactory(factory.address);

    const blockNumber = await getBlockNumber();

    const minLockTime = 3600 * 24 * 7 * 16;

    pool = await deployUtils.deployProxy(
      "CorePoolMock",
      lfg.address,
      blockNumber + 2,
      minLockTime,
      amountReservedToPool,
      factory.address
    );

    await lfg.setPool(pool.address);
  }

  beforeEach(async function () {
    await initAndDeploy();
  });

  async function getApy(amount, lockedTime) {
    const blocksInAYear = blocksPerDay * 365;
    let usersLockingWeight = await pool.usersLockingWeight();
    const totalYieldOverYear = ethers.BigNumber.from(tokenPerBlock.toString()).mul(blocksInAYear);
    const depositWeight = await pool.getStakeWeight(lockedTime, amount);
    const yieldOnAmount = totalYieldOverYear.mul(depositWeight).div(depositWeight.add(usersLockingWeight));
    // this is an approximation of the APY, applying a factor to confirm the result validated in tests
    return yieldOnAmount.mul(100).div(amount).mul(3720).div(10000).toNumber();
  }

  it.only("should let bob stake some LFG and get rewards after 10 days", async function () {
    await lfg.connect(tokenHolder).transfer(bob.address, ethers.utils.parseEther("10000"));
    await lfg.connect(bob).approve(pool.address, ethers.utils.parseEther("10000"));

    let ts = await getTimestamp();

    await pool.connect(bob).stake(ethers.utils.parseEther("500"), ts + 3600 * 24 * 7 * 20);
    const user = await pool.users(bob.address);
    console.log(user);

    await increaseBlockTimestampBy(3600 * 24 * 7);
    let blockNumber = (await ethers.provider.getBlock()).number;
    await pool.setFakeBlockNumber(blockNumber + blocksPerWeek);
    await pool.sync();
    // await pool.updateLFGPerBlock();

    let bobBalanceBefore = await lfg.balanceOf(bob.address);
    // let pendingYieldingRewards = await pool.pendingYieldRewards(bob.address);

    await pool.connect(bob).processRewards();

    let bobBalanceAfter = await lfg.balanceOf(bob.address);
    expect(bobBalanceBefore).equal("9500000000000000000000");
    expect(bobBalanceAfter).equal("12017201473684210523792263");
    expect(bobBalanceAfter.sub(bobBalanceBefore)).equal("12504237181996086099365490");

    const deposit = await pool.getDeposit(bob.address, 0);
    const unstakeAmount = deposit.tokenAmount.div(2);

    await expect(pool.connect(bob).unstake(0, unstakeAmount)).revertedWith("TooEarlyToUnstake()");

    await increaseBlockTimestampBy(3600 * 24 * 7 * 20);
    blockNumber = await pool.blockNumber();
    await pool.setFakeBlockNumber(blockNumber + blocksPerWeek * 20);

    bobBalanceBefore = await lfg.balanceOf(bob.address);
    pendingYieldingRewards = await pool.pendingYieldRewards(bob.address);
    const depositLength = await pool.getDepositsLength(bob.address);
    expect(depositLength).to.be.equal(1);
    await expect(pool.connect(bob).unstake(0, unstakeAmount)).to.emit(pool, "Unstaked").withArgs(bob.address, unstakeAmount);
    bobBalanceAfter = await lfg.balanceOf(bob.address);
    expect(bobBalanceAfter.sub(bobBalanceBefore).div(pendingYieldingRewards)).lt(1);

    await increaseBlockTimestampBy(3600 * 24);
    blockNumber = await pool.blockNumber();
    await pool.setFakeBlockNumber(blockNumber + blocksPerDay);

    await expect(pool.connect(bob).unstake(0, unstakeAmount)).to.emit(pool, "Unstaked").withArgs(bob.address, unstakeAmount);

    const balanceNow = await lfg.balanceOf(bob.address);
    expect(balanceNow.sub(bobBalanceAfter)).to.be.equal("250000000000000000000");
  });

  it("should let bob stake some LFG and get rewards after 10 days", async function () {
    await lfg.connect(tokenHolder).transfer(bob.address, ethers.utils.parseEther("100000"));
    await lfg.connect(tokenHolder).transfer(alice.address, ethers.utils.parseEther("100000"));
    await lfg.connect(tokenHolder).transfer(fred.address, ethers.utils.parseEther("100000"));
    await lfg.connect(tokenHolder).transfer(red.address, ethers.utils.parseEther("100000"));
    await lfg.connect(tokenHolder).transfer(lee.address, ethers.utils.parseEther("100000"));
    await lfg.connect(tokenHolder).transfer(jane.address, ethers.utils.parseEther("100000"));
    await lfg.connect(tokenHolder).transfer(jim.address, ethers.utils.parseEther("10000"));

    await lfg.connect(bob).approve(pool.address, ethers.utils.parseEther("100000"));
    await lfg.connect(alice).approve(pool.address, ethers.utils.parseEther("100000"));
    await lfg.connect(fred).approve(pool.address, ethers.utils.parseEther("100000"));
    await lfg.connect(red).approve(pool.address, ethers.utils.parseEther("100000"));
    await lfg.connect(lee).approve(pool.address, ethers.utils.parseEther("100000"));
    await lfg.connect(jane).approve(pool.address, ethers.utils.parseEther("100000"));
    await lfg.connect(jim).approve(pool.address, ethers.utils.parseEther("10000"));

    let ts = await getTimestamp();

    // bob, alice, fred, jim, red, lee, jane
    // many users do many stakes

    await pool.connect(bob).stake(ethers.utils.parseEther("500"), ts + 3600 * 24 * 7 * 20);
    await pool.connect(alice).stake(ethers.utils.parseEther("100"), ts + 3600 * 24 * 7 * 40);
    await pool.connect(fred).stake(ethers.utils.parseEther("500"), ts + 3600 * 24 * 7 * 50);
    await pool.connect(fred).stake(ethers.utils.parseEther("500"), ts + 3600 * 24 * 7 * 20);
    await pool.connect(red).stake(ethers.utils.parseEther("100"), ts + 3600 * 24 * 7 * 40);
    await pool.connect(lee).stake(ethers.utils.parseEther("500"), ts + 3600 * 24 * 7 * 50);
    await pool.connect(lee).stake(ethers.utils.parseEther("500"), ts + 3600 * 24 * 7 * 20);
    await pool.connect(bob).stake(ethers.utils.parseEther("100"), ts + 3600 * 24 * 7 * 40);
    await pool.connect(alice).stake(ethers.utils.parseEther("500"), ts + 3600 * 24 * 7 * 50);

    // first case

    let balanceBefore = await lfg.balanceOf(jane.address);
    let amount = ethers.utils.parseEther("100000");
    expect(balanceBefore).to.equal(amount);

    let twentyWeeks = 3600 * 24 * 7 * 20;
    let twentyWeeksFromNow = ts + twentyWeeks;

    let apy = await getApy(amount, twentyWeeks);

    await pool.connect(jane).stake(amount, twentyWeeksFromNow);

    let blockNumber = (await ethers.provider.getBlock()).number;
    await increaseBlockTimestampBy(twentyWeeks);

    await pool.setFakeBlockNumber(blockNumber + blocksPerWeek * 20);

    await pool.connect(jane).unstake(0, amount);
    let balanceAfter = await lfg.balanceOf(jane.address);

    let percentile = amount.div(100);
    let increase = balanceAfter.sub(amount).div(percentile);

    // we prove they are in the same order of magnitude
    expect(increase.mul(10).div(apy).sub(10).abs()).lt(5);

    // second case

    balanceBefore = await lfg.balanceOf(jim.address);
    amount = ethers.utils.parseEther("10000");
    expect(balanceBefore).to.equal(amount);

    let aYear = 3600 * 24 * 365;

    apy = await getApy(amount, aYear);

    await pool.connect(jim).stake(amount, ts + aYear);

    blockNumber = (await ethers.provider.getBlock()).number;
    await increaseBlockTimestampBy(aYear);

    await pool.setFakeBlockNumber(blockNumber + blocksPerDay * 365);

    await pool.connect(jim).unstake(0, amount);
    balanceAfter = await lfg.balanceOf(jim.address);

    percentile = amount.div(100);
    increase = balanceAfter.div(percentile);
    expect(increase.mul(10).div(apy).sub(10).abs()).lt(5);
  });

  async function formatBalance(b) {
    b = ethers.utils.formatEther(b);
    return Math.round(parseFloat(b) * 100) / 100;
  }

  async function formattedBalanceOf(user) {
    return formatBalance(await lfg.balanceOf(user.address));
  }

  it("should let bob, alice and fred stake some LFG and get rewards", async function () {
    await lfg.connect(tokenHolder).transfer(bob.address, ethers.utils.parseEther("100000"));
    await lfg.connect(bob).approve(pool.address, ethers.utils.parseEther("10000"));
    await lfg.connect(tokenHolder).transfer(alice.address, ethers.utils.parseEther("10000"));
    await lfg.connect(alice).approve(pool.address, ethers.utils.parseEther("10000"));
    await lfg.connect(tokenHolder).transfer(fred.address, ethers.utils.parseEther("10000"));
    await lfg.connect(fred).approve(pool.address, ethers.utils.parseEther("10000"));

    let ts = await getTimestamp();

    await pool.connect(bob).stake(ethers.utils.parseEther("500"), ts + 1 + 3600 * 24 * 7 * 16);
    await pool.connect(alice).stake(ethers.utils.parseEther("500"), ts + 3600 * 24 * 365);
    await pool.connect(fred).stake(ethers.utils.parseEther("500"), ts + 3600 * 24 * 180);

    let blockNumber = (await ethers.provider.getBlock()).number;
    await increaseBlockTimestampBy(3600 * 24 * 10);
    await pool.setFakeBlockNumber(blockNumber + blocksPerDay * 10);

    let bobBalanceBefore = await formattedBalanceOf(bob);
    let pendingYieldingRewards = await pool.pendingYieldRewards(bob.address);
    expect(pendingYieldingRewards).to.be.equal("3647586897352538936716320");
    await pool.connect(bob).processRewards();
    let bobBalanceAfter = await formattedBalanceOf(bob);
    let gain = bobBalanceAfter - bobBalanceBefore;
    let yield = await formatBalance(pendingYieldingRewards);
    let ratio = gain / yield;
    expect(ratio).lt(1);

    pendingYieldingRewards = await pool.pendingYieldRewards(alice.address);
    expect(pendingYieldingRewards).to.be.equal("5414757760595613942076035");
    pendingYieldingRewards = await pool.pendingYieldRewards(fred.address);
    expect(pendingYieldingRewards).to.be.equal("4042510393281258941902750");
  });
});
