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

  async function initAndDeploy(_reservedToPool) {
    let maxSupply = bn("3000000000");
    let initialSupply = bn("900000000");
    let amountReservedToSharesPool = bn("200000000");

    if (_reservedToPool) {
      amountReservedToPool = bn(_reservedToPool.toString());
    }

    // pool configuration
    tokenPerBlock = 42530984996738421395n;
    // ^ calculated using scripts/calculate-token-per-block.js for a 2 years pool with 97% decay factor
    // and a reserved amount of 400M tokens.

    // console.log(tokenPerBlock / 1000000000000000000n);

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

  it("should let bob stake some LFG and get rewards", async function () {
    await lfg.connect(tokenHolder).transfer(bob.address, bn("10000"));
    await lfg.connect(bob).approve(pool.address, bn("10000"));

    let ts = await getTimestamp();

    await pool.connect(bob).stake(bn("500"), ts + 3600 * 24 * 7 * 20);
    // const user = await pool.users(bob.address);
    // console.log(user);

    await increaseBlocksBy(3600 * 24 * 7);
    await pool.sync();
    // await pool.updateLFGPerBlock();

    let bobBalanceBefore = await lfg.balanceOf(bob.address);
    // let pendingYieldingRewards = await pool.pendingYieldRewards(bob.address);

    await pool.connect(bob).processRewards();

    let bobBalanceAfter = await lfg.balanceOf(bob.address);
    expect(bobBalanceBefore).equal("9500000000000000000000");
    expect(bobBalanceAfter).equal("12017160631578947365103517");
    expect(bobBalanceAfter.sub(bobBalanceBefore)).equal("12007660631578947365103517");

    const deposit = await pool.getDeposit(bob.address, 0);
    const unstakeAmount = deposit.tokenAmount.div(2);

    await expect(pool.connect(bob).unstake(0, unstakeAmount)).revertedWith("TooEarlyToUnstake()");

    await increaseBlocksBy(3600 * 24 * 7 * 21);

    bobBalanceBefore = await lfg.balanceOf(bob.address);
    let pendingYieldingRewards = await pool.pendingYieldRewards(bob.address);
    const depositLength = await pool.getDepositsLength(bob.address);
    expect(depositLength).to.be.equal(1);
    await expect(pool.connect(bob).unstake(0, unstakeAmount)).to.emit(pool, "Unstaked").withArgs(bob.address, unstakeAmount);
    bobBalanceAfter = await lfg.balanceOf(bob.address);

    await increaseBlocksBy(3600 * 25);

    await expect(pool.connect(bob).unstake(0, unstakeAmount)).to.emit(pool, "Unstaked").withArgs(bob.address, unstakeAmount);

    const balanceNow = await lfg.balanceOf(bob.address);
    expect(balanceNow.sub(bobBalanceAfter)).to.be.equal("942795933103683426321678");
  });

  // GET APY

  async function getApy(userAddress, amount, lockedTime) {
    let poolConfig = await pool.getConfig();
    let endBlock = poolConfig.endBlock.toNumber();
    let lockedBlocks = (lockedTime / (3600 * 24)) * 42000;
    let [tokensPerBlock, totalYieldRewards, yieldRewardsPerWeight, , usersLockingWeight, lastYieldDistribution] =
      await pool.getCurrentValues();
    // we get the value of tokensPerBlock at the time the claim happens
    let numberOfWeeks = lockedBlocks / poolConfig.blocksPerUpdate.toNumber();
    for (let i = 0; i < numberOfWeeks; i++) {
      tokensPerBlock = tokensPerBlock.mul(poolConfig.decayFactor).div(100);
    }
    const newWeight = await pool.getStakeWeight(lockedTime, amount);
    usersLockingWeight = usersLockingWeight.add(newWeight);
    let futureBlockNumber = lockedBlocks + (await pool.blockNumber()).toNumber();
    let multiplier =
      futureBlockNumber > endBlock
        ? endBlock - lastYieldDistribution.toNumber()
        : futureBlockNumber - lastYieldDistribution.toNumber();
    let rewards = tokensPerBlock.mul(multiplier);
    let newYieldRewardsPerWeight = rewards
      .mul(poolConfig.rewardPerWeightMultiplier)
      .div(usersLockingWeight)
      .add(yieldRewardsPerWeight);
    let user = await pool.users(userAddress);

    let userTotalWeight = user.totalWeight.add(newWeight);
    let userSubYieldRewards = userTotalWeight.mul(yieldRewardsPerWeight).div(poolConfig.rewardPerWeightMultiplier);
    let expected = userTotalWeight
      .mul(newYieldRewardsPerWeight)
      .div(poolConfig.rewardPerWeightMultiplier)
      .sub(userSubYieldRewards);
    return expected.div(amount).toNumber();
  }

  function bn2n(bn) {
    return Number(bn.div("1000000000000000000").toString());
  }

  it("should let bob stake some LFG and get rewards checking the APY", async function () {
    let users = [bob, alice, fred, jim, red, lee, jane];
    let ts = await getTimestamp();
    for (let user of users) {
      await lfg.connect(tokenHolder).transfer(user.address, bn(1000000));
      await lfg.connect(user).approve(pool.address, bn(1000000));
      if (user.address !== jane.address && user.address !== jim.address) {
        const amount = bn(30000 + Math.round(70000 * Math.random()));
        const lockedUntil = Math.round(ts + 3600 * 24 * 7 * (16 + (52 - 16) * Math.random()));
        await pool.connect(user).stake(amount, lockedUntil);
      }
    }

    // first case

    let balanceBefore = await lfg.balanceOf(jane.address);
    let amount = bn("100000");

    let twentyWeeks = 3600 * 24 * 7 * 20;

    let apy = await getApy(jane.address, amount, twentyWeeks);
    // console.log("apy", apy);

    await pool.connect(jane).stake(amount, ts + twentyWeeks);

    await increaseBlocksBy(twentyWeeks + week);
    // console.log("Pending rewards", bn2n(await pool.pendingYieldRewards(jane.address)));
    await pool.connect(jane).processRewards();
    let balanceAfter = await lfg.balanceOf(jane.address);

    let balanceAfter2 = bn2n(balanceAfter);
    let balanceBefore2 = bn2n(balanceBefore);

    let increase = (balanceAfter2 - balanceBefore2) / bn2n(amount);
    // console.log("got", balanceAfter2 - balanceBefore2);
    // console.log("Increase", increase)
    expect(increase / apy < 10).to.be.true;

    // we prove they are in the same order of magnitude
    // expect(increase / apy < 10).to.be.true;

    // second case

    balanceBefore = await lfg.balanceOf(jim.address);
    amount = bn("900000");

    let aYear = 3600 * 24 * 365;

    apy = await getApy(jim.address, amount, aYear);
    // console.log("apy", apy);

    // console.log(await pool.blockNumber())
    await pool.connect(jim).stake(amount, ts + aYear);

    await increaseBlocksBy(aYear + week);
    // console.log("Pending rewards", bn2n(await pool.pendingYieldRewards(jim.address)));
    // console.log(await pool.blockNumber())
    await pool.connect(jim).processRewards();
    balanceAfter = await lfg.balanceOf(jim.address);

    balanceAfter2 = bn2n(balanceAfter);
    balanceBefore2 = bn2n(balanceBefore);

    increase = (balanceAfter2 - balanceBefore2) / bn2n(amount);
    // console.log("got", balanceAfter2 - balanceBefore2);
    // console.log("Increase", increase)
    // expect(increase / apy < 10).to.be.true;
  });

  it("should let bob stake some LFG and get rewards and APY after 20 weeks", async function () {
    await lfg.connect(tokenHolder).transfer(jane.address, bn("1000"));
    await lfg.connect(jane).approve(pool.address, bn("1000"));

    let ts = await getTimestamp();

    let balanceBefore = await lfg.balanceOf(jane.address);
    let amount = bn("1000");
    expect(balanceBefore).to.equal(amount);

    let twentyWeeks = 3600 * 24 * 7 * 20;

    let apy = await getApy(jane.address, amount, twentyWeeks);
    // console.log("apy", apy);

    await pool.connect(jane).stake(amount, ts + twentyWeeks);

    await increaseBlocksBy(twentyWeeks);
    // console.log("Pending rewards", bn2n(await pool.pendingYieldRewards(jane.address)));
    await pool.connect(jane).processRewards();
    let balanceAfter = await lfg.balanceOf(jane.address);

    let balanceAfter2 = bn2n(balanceAfter);
    let balanceBefore2 = bn2n(balanceBefore);

    let increase = (balanceAfter2 - balanceBefore2) / bn2n(amount);
    // console.log("got", balanceAfter2 - balanceBefore2);
    // console.log("Increase", increase)

    // we prove they are in the same order of magnitude
    expect(increase / apy < 10).to.be.true;
  });

  async function formatBalance(b) {
    b = ethers.utils.formatEther(b);
    return Math.round(parseFloat(b) * 100) / 100;
  }

  async function formattedBalanceOf(user) {
    return formatBalance(await lfg.balanceOf(user.address));
  }

  it("should let bob, alice and fred stake some LFG and get rewards", async function () {
    await lfg.connect(tokenHolder).transfer(bob.address, bn("100000"));
    await lfg.connect(bob).approve(pool.address, bn("10000"));
    await lfg.connect(tokenHolder).transfer(alice.address, bn("10000"));
    await lfg.connect(alice).approve(pool.address, bn("10000"));
    await lfg.connect(tokenHolder).transfer(fred.address, bn("10000"));
    await lfg.connect(fred).approve(pool.address, bn("10000"));

    let ts = await getTimestamp();

    await pool.connect(bob).stake(bn("500"), ts + 1 + 3600 * 24 * 7 * 16);
    await pool.connect(alice).stake(bn("500"), ts + 3600 * 24 * 365);
    await pool.connect(fred).stake(bn("500"), ts + 3600 * 24 * 180);

    await increaseBlocksBy(3600 * 24 * 10);

    let bobBalanceBefore = await formattedBalanceOf(bob);
    let pendingYieldingRewards = await pool.pendingYieldRewards(bob.address);
    expect(pendingYieldingRewards).to.be.equal("4670326327829435881481585");
    await pool.connect(bob).processRewards();
    let bobBalanceAfter = await formattedBalanceOf(bob);
    let gain = bobBalanceAfter - bobBalanceBefore;
    let yield = await formatBalance(pendingYieldingRewards);
    let ratio = gain / yield;
    expect(ratio).lt(1.2);

    pendingYieldingRewards = await pool.pendingYieldRewards(alice.address);
    expect(pendingYieldingRewards).to.be.equal("7147410308464601164228875");
    pendingYieldingRewards = await pool.pendingYieldRewards(fred.address);
    expect(pendingYieldingRewards).to.be.equal("5336061507179136762500625");
  });

  it("should verify that if all stakes the distributed rewards are compatible with the reserved amount", async function () {
    let _reservedToPool = 400000000;
    for (let i = 0; i < 10; i++) {
      await initAndDeploy(_reservedToPool);

      await lfg.connect(tokenHolder).transfer(bob.address, bn("1000"));
      await lfg.connect(bob).approve(pool.address, bn("2000"));
      await lfg.connect(tokenHolder).transfer(alice.address, bn("1000"));
      await lfg.connect(alice).approve(pool.address, bn("1000"));
      await lfg.connect(tokenHolder).transfer(fred.address, bn("1000"));
      await lfg.connect(fred).approve(pool.address, bn("1000"));

      // stake for
      await pool.connect(bob).stake(bn("500"), (await getTimestamp()) + 3600 * 24 * 7 * 17);
      await pool.connect(alice).stake(bn("500"), (await getTimestamp()) + 3600 * 24 * 7 * 32);
      await pool.connect(fred).stake(bn("500"), (await getTimestamp()) + 3600 * 24 * 7 * 52);

      await increaseBlocksBy(3600 * 24);
      let bobBalance = await formattedBalanceOf(bob);
      await expect(pool.connect(bob).stake(bn("50"), (await getTimestamp()) + 3600 * 24 * 7 * 17))
        .to.emit(pool, "Staked")
        .withArgs(bob.address, bn("50"), (await getTimestamp()) + 1, (await getTimestamp()) + 3600 * 24 * 7 * 17);

      let bobBalance2 = await formattedBalanceOf(bob);
      let gain = bobBalance2 - bobBalance - 50;

      await increaseBlocksBy(3600 * 24 * 7 * 52);

      await pool.connect(bob).stake(bn("500"), (await getTimestamp()) + 3600 * 24 * 7 * 17);
      await pool.connect(alice).stake(bn("500"), (await getTimestamp()) + 3600 * 24 * 7 * 32);
      await pool.connect(fred).stake(bn("500"), (await getTimestamp()) + 3600 * 24 * 7 * 52);

      await increaseBlocksBy(3600 * 24 * 7 * 53);

      await pool.connect(bob).processRewards();
      await pool.connect(alice).processRewards();
      await pool.connect(fred).processRewards();

      bobBalance = await formattedBalanceOf(bob);
      let aliceBalance = await formattedBalanceOf(alice);
      let fredBalance = await formattedBalanceOf(fred);

      let totalDistributedRewards = parseFloat(bobBalance) + parseFloat(aliceBalance) + parseFloat(fredBalance);
      // console.debug(totalDistributedRewards);
      // console.debug(_reservedToPool);

      expect(totalDistributedRewards).lt(_reservedToPool);

      _reservedToPool -= 30000000;
    }
  });

  async function increaseBlocksBy(seconds) {
    let blockNumber = (await pool.blockNumber()).toNumber();
    // console.log("increasing blocks by", seconds, "seconds, and", Math.floor(blocksPerDay * (seconds / 86400)), "blocks.");
    await increaseBlockTimestampBy(seconds);
    let newBlockNumber = blockNumber + Math.floor((blocksPerDay * seconds) / 86400);
    await pool.setFakeBlockNumber(newBlockNumber);
    return newBlockNumber;
  }

  it("should update stake lock", async function () {
    let _reservedToPool = 400000000;
    await initAndDeploy(_reservedToPool);

    await lfg.connect(tokenHolder).transfer(bob.address, ethers.utils.parseEther("1000"));
    await lfg.connect(bob).approve(pool.address, ethers.utils.parseEther("1000"));
    await lfg.connect(tokenHolder).transfer(alice.address, ethers.utils.parseEther("1000"));
    await lfg.connect(alice).approve(pool.address, ethers.utils.parseEther("1000"));
    await lfg.connect(tokenHolder).transfer(fred.address, ethers.utils.parseEther("1000"));
    await lfg.connect(fred).approve(pool.address, ethers.utils.parseEther("1000"));

    // stake for
    await pool.connect(bob).stake(ethers.utils.parseEther("500"), (await getTimestamp()) + 3600 * 24 * 7 * 17);
    await pool.connect(alice).stake(ethers.utils.parseEther("500"), (await getTimestamp()) + 3600 * 24 * 7 * 32);
    await pool.connect(fred).stake(ethers.utils.parseEther("500"), (await getTimestamp()) + 3600 * 24 * 7 * 52);

    let depositBefore = await pool.connect(bob).getDeposit(bob.address, 0);

    await pool.connect(bob).updateStakeLock(0, (await getTimestamp()) + 3600 * 24 * 7 * 18);

    let depositAfter = await pool.connect(bob).getDeposit(bob.address, 0);
    expect(Number(depositAfter.lockedUntil)).greaterThan(Number(depositBefore.lockedUntil));
  });

  it("should revert invaid stake lock", async function () {
    let _reservedToPool = 400000000;
    await initAndDeploy(_reservedToPool);

    await lfg.connect(tokenHolder).transfer(bob.address, ethers.utils.parseEther("1000"));
    await lfg.connect(bob).approve(pool.address, ethers.utils.parseEther("1000"));
    await lfg.connect(tokenHolder).transfer(alice.address, ethers.utils.parseEther("1000"));
    await lfg.connect(alice).approve(pool.address, ethers.utils.parseEther("1000"));
    await lfg.connect(tokenHolder).transfer(fred.address, ethers.utils.parseEther("1000"));
    await lfg.connect(fred).approve(pool.address, ethers.utils.parseEther("1000"));

    // stake for
    await pool.connect(bob).stake(ethers.utils.parseEther("500"), (await getTimestamp()) + 3600 * 24 * 7 * 17);
    await pool.connect(alice).stake(ethers.utils.parseEther("500"), (await getTimestamp()) + 3600 * 24 * 7 * 32);
    await pool.connect(fred).stake(ethers.utils.parseEther("500"), (await getTimestamp()) + 3600 * 24 * 7 * 52);

    await expect(pool.connect(bob).updateStakeLock(0, (await getTimestamp()) + 3600 * 24 * 7 * 10)).revertedWith(
      "InvalidNewLock()"
    );
  });

  it("should revert Max Lock Period Is 365Days", async function () {
    let _reservedToPool = 400000000;
    await initAndDeploy(_reservedToPool);

    await lfg.connect(tokenHolder).transfer(bob.address, ethers.utils.parseEther("1000"));
    await lfg.connect(bob).approve(pool.address, ethers.utils.parseEther("1000"));
    await lfg.connect(tokenHolder).transfer(alice.address, ethers.utils.parseEther("1000"));
    await lfg.connect(alice).approve(pool.address, ethers.utils.parseEther("1000"));
    await lfg.connect(tokenHolder).transfer(fred.address, ethers.utils.parseEther("1000"));
    await lfg.connect(fred).approve(pool.address, ethers.utils.parseEther("1000"));

    // stake for
    let blockNumber = (await ethers.provider.getBlock()).number;
    await pool.connect(bob).stake(ethers.utils.parseEther("500"), (await getTimestamp()) + 3600 * 24 * 7 * 17);
    await pool.connect(alice).stake(ethers.utils.parseEther("500"), (await getTimestamp()) + 3600 * 24 * 7 * 32);
    await pool.connect(fred).stake(ethers.utils.parseEther("500"), (await getTimestamp()) + 3600 * 24 * 7 * 52);

    blockNumber = (await ethers.provider.getBlock()).number;
    await increaseBlockTimestampBy(3600 * 24 * 7 * 53);
    await pool.setFakeBlockNumber(blockNumber + blocksPerDay * 366);

    await expect(pool.connect(bob).updateStakeLock(0, (await getTimestamp()) + 3600 * 24 * 7 * 10)).revertedWith(
      "MaxLockPeriodIs365Days()"
    );
  });

  it("should read stake succesfully", async function () {
    let _reservedToPool = 400000000;
    await initAndDeploy(_reservedToPool);

    await lfg.connect(tokenHolder).transfer(bob.address, ethers.utils.parseEther("1000"));
    await lfg.connect(bob).approve(pool.address, ethers.utils.parseEther("1000"));
    await lfg.connect(tokenHolder).transfer(alice.address, ethers.utils.parseEther("1000"));
    await lfg.connect(alice).approve(pool.address, ethers.utils.parseEther("1000"));
    await lfg.connect(tokenHolder).transfer(fred.address, ethers.utils.parseEther("1000"));
    await lfg.connect(fred).approve(pool.address, ethers.utils.parseEther("1000"));

    await pool.connect(bob).stake(ethers.utils.parseEther("500"), (await getTimestamp()) + 3600 * 24 * 7 * 17);

    expect(await pool.connect(bob).balanceOf(bob.address)).to.be.equal("500000000000000000000");
  });
});
