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
const {max} = require("hardhat/internal/util/bigint");

describe("CorePool", function () {
  let factory;
  let lfg;
  let pool;
  let owner, operator, validator, tokenHolder, bob, alice, fred, jim, red, lee, jane;
  let tokenPerBlock;

  function bn(v) {
    return ethers.utils.parseEther(v.toString());
  }

  const week = 3600 * 24 * 7;
  const blocksPerDay = 42000;
  const blocksPerWeek = blocksPerDay * 7;
  const twoYearsBlocks = blocksPerDay * 365 * 2;
  const reservedToTool = 400000000;
  let amountReservedToPool = bn(reservedToTool.toString());
  const minLockTime = 3600 * 24 * 7 * 16;

  before(async function () {
    [owner, operator, validator, tokenHolder, bob, alice, fred, jim, red, lee, jane] = await ethers.getSigners();
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
    // ^ calculated using scripts/calculate-tokenPerBlock.js for a 2 years pool with 97% decay factor
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
    expect(bobBalanceAfter).equal("15203638799999998437335");
    expect(bobBalanceAfter.sub(bobBalanceBefore)).equal("5703638799999998437335");

    const deposit = await pool.getDeposit(bob.address, 0);
    const unstakeAmount = deposit.tokenAmount.div(2);

    await expect(pool.connect(bob).unstake(0, unstakeAmount)).revertedWith("TooEarlyToUnstake()");

    await increaseBlocksBy(3600 * 24 * 7 * 21);

    bobBalanceBefore = await lfg.balanceOf(bob.address);
    pendingYieldingRewards = await pool.pendingYieldRewards(bob.address);
    const depositLength = await pool.getDepositsLength(bob.address);
    expect(depositLength).to.be.equal(1);
    await expect(pool.connect(bob).unstake(0, unstakeAmount)).to.emit(pool, "Unstaked").withArgs(bob.address, unstakeAmount);
    bobBalanceAfter = await lfg.balanceOf(bob.address);
    expect(bobBalanceAfter.sub(bobBalanceBefore).div(pendingYieldingRewards)).lt(1);

    await increaseBlocksBy(3600 * 25);

    await expect(pool.connect(bob).unstake(0, unstakeAmount)).to.emit(pool, "Unstaked").withArgs(bob.address, unstakeAmount);

    const balanceNow = await lfg.balanceOf(bob.address);
    expect(balanceNow.sub(bobBalanceAfter)).to.be.equal("35139186396164776256721");
  });

  async function getApy(amount, lockedTime) {
    const blocksInAYear = blocksPerDay * 365;
    let usersLockingWeight = await pool.usersLockingWeight();
    const totalYieldOverYear = ethers.BigNumber.from(tokenPerBlock.toString()).mul(blocksInAYear);
    const depositWeight = await pool.getStakeWeight(lockedTime, amount);
    const yieldOnAmount = totalYieldOverYear.mul(depositWeight).div(depositWeight.add(usersLockingWeight));
    // console.log(yieldOnAmount.mul(100).div(amount).div(10000).toNumber());
    return yieldOnAmount.mul(100).div(amount).div(10000).toNumber();
  }

  it.only("should let bob stake some LFG and get rewards after 10 days", async function () {
    await lfg.connect(tokenHolder).transfer(bob.address, bn("100000"));
    await lfg.connect(tokenHolder).transfer(alice.address, bn("100000"));
    await lfg.connect(tokenHolder).transfer(fred.address, bn("100000"));
    await lfg.connect(tokenHolder).transfer(red.address, bn("100000"));
    await lfg.connect(tokenHolder).transfer(lee.address, bn("100000"));
    await lfg.connect(tokenHolder).transfer(jane.address, bn("100000"));
    await lfg.connect(tokenHolder).transfer(jim.address, bn("10000"));

    await lfg.connect(bob).approve(pool.address, bn("100000"));
    await lfg.connect(alice).approve(pool.address, bn("100000"));
    await lfg.connect(fred).approve(pool.address, bn("100000"));
    await lfg.connect(red).approve(pool.address, bn("100000"));
    await lfg.connect(lee).approve(pool.address, bn("100000"));
    await lfg.connect(jane).approve(pool.address, bn("100000"));
    await lfg.connect(jim).approve(pool.address, bn("10000"));

    let ts = await getTimestamp();

    // bob, alice, fred, jim, red, lee, jane
    // many users do many stakes

    await pool.connect(bob).stake(bn("500"), ts + 3600 * 24 * 7 * 20);
    await pool.connect(alice).stake(bn("100"), ts + 3600 * 24 * 7 * 40);
    await pool.connect(fred).stake(bn("500"), ts + 3600 * 24 * 7 * 50);
    await pool.connect(fred).stake(bn("500"), ts + 3600 * 24 * 7 * 20);
    await pool.connect(red).stake(bn("100"), ts + 3600 * 24 * 7 * 40);
    await pool.connect(lee).stake(bn("500"), ts + 3600 * 24 * 7 * 50);
    await pool.connect(lee).stake(bn("500"), ts + 3600 * 24 * 7 * 20);
    await pool.connect(bob).stake(bn("100"), ts + 3600 * 24 * 7 * 40);
    await pool.connect(alice).stake(bn("500"), ts + 3600 * 24 * 7 * 50);

    // first case

    let balanceBefore = await lfg.balanceOf(jane.address);
    let amount = bn("100000");
    expect(balanceBefore).to.equal(amount);

    let twentyWeeks = 3600 * 24 * 7 * 20;
    let twentyWeeksFromNow = ts + twentyWeeks;

    let apy = await getApy(amount, twentyWeeks);

    await pool.connect(jane).stake(amount, twentyWeeksFromNow);

    await increaseBlocksBy(twentyWeeks + week);

    await pool.connect(jane).unstake(0, amount);
    let balanceAfter = await lfg.balanceOf(jane.address);

    let increase = Math.round(
      (100 * parseFloat(ethers.utils.formatEther(balanceBefore))) / parseFloat(ethers.utils.formatEther(balanceAfter))
    );

    // we prove they are in the same order of magnitude
    expect(increase / apy < 10).to.be.true;

    // second case

    balanceBefore = await lfg.balanceOf(jim.address);
    amount = bn("10000");
    expect(balanceBefore).to.equal(amount);

    let aYear = 3600 * 24 * 365;

    apy = await getApy(amount, aYear);

    // console.log(await pool.blockNumber())
    await pool.connect(jim).stake(amount, ts + aYear);

    await increaseBlocksBy(aYear + week);
    // console.log(await pool.blockNumber())
    await pool.connect(jim).unstake(0, amount);
    balanceAfter = await lfg.balanceOf(jim.address);

    increase = Math.round(
      (100 * parseFloat(ethers.utils.formatEther(balanceBefore))) / parseFloat(ethers.utils.formatEther(balanceAfter))
    );
    expect(increase / apy < 10).to.be.true;
  });

  it("should let bob stake some LFG and get rewards after 10 days", async function () {
    await lfg.connect(tokenHolder).transfer(jane.address, bn("1000"));
    await lfg.connect(jane).approve(pool.address, bn("1000"));

    let ts = await getTimestamp();

    let balanceBefore = await lfg.balanceOf(jane.address);
    let amount = bn("1000");
    expect(balanceBefore).to.equal(amount);

    let twentyWeeks = 3600 * 24 * 7 * 20;
    let twentyWeeksFromNow = ts + twentyWeeks;

    let apy = await getApy(amount, twentyWeeks);

    await pool.connect(jane).stake(amount, twentyWeeksFromNow);

    // console.log(await increaseBlocksBy(twentyWeeks));

    await pool.connect(jane).unstake(0, amount);
    let balanceAfter = await lfg.balanceOf(jane.address);

    let increase = Math.round(
      (100 * parseFloat(ethers.utils.formatEther(balanceBefore))) / parseFloat(ethers.utils.formatEther(balanceAfter))
    );
    // console.log(apy)

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
    expect(pendingYieldingRewards).to.be.equal("914805842722520265402");
    await pool.connect(bob).processRewards();
    let bobBalanceAfter = await formattedBalanceOf(bob);
    let gain = bobBalanceAfter - bobBalanceBefore;
    let yield = await formatBalance(pendingYieldingRewards);
    let ratio = gain / yield;
    expect(ratio).lt(1);

    pendingYieldingRewards = await pool.pendingYieldRewards(alice.address);
    expect(pendingYieldingRewards).to.be.equal("1302007829941614527072");
    pendingYieldingRewards = await pool.pendingYieldRewards(fred.address);
    expect(pendingYieldingRewards).to.be.equal("972043369400568561125");
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

  it.skip("should simulate the entire history of the pool", async function () {
    this.timeout(300000);
    let deposits = {};
    let users = [bob, alice, fred, jim, red, lee, jane];
    let names = {};
    names[bob.address] = "bob";
    names[alice.address] = "alice";
    names[fred.address] = "fred";
    names[jim.address] = "jim";
    names[red.address] = "red";
    names[lee.address] = "lee";
    names[jane.address] = "jane";
    let maxStaked = {};
    let staked = {};
    for (let u of users) {
      deposits[u.address] = [];
      maxStaked[u.address] = 0n;
      staked[u.address] = 0n;
      await lfg.connect(tokenHolder).transfer(u.address, bn("10000000"));
    }
    let blockNumber = (await ethers.provider.getBlock()).number;
    let endBlock = (await pool.getConfig()).endBlock;
    let ts = await getTimestamp();
    let ts0 = ts;
    let failed = false;
    let count = 0;
    async function randomAction() {
      let day = 3600 * 24;
      let week = day * 7;
      let time = Math.floor((Math.random() * day) / 4);
      ts += time;
      blockNumber = await increaseBlocksBy(time);
      let lockUntil = (await getTimestamp()) + minLockTime + Math.floor(Math.random() * (week * 51 - minLockTime));
      let user = users[Math.floor(Math.random() * users.length)];
      let func = Math.random() * 100;
      let amount = 10 + Math.floor(Math.random() * 50000);
      for (let address in deposits) {
        let ds = deposits[address];
        for (let i = 0; i < ds.length; i++) {
          let d = ds[i];
          if (d.lockUntil && d.lockUntil < ts) {
            console.log(names[address], "unstakes", d.amount);
            staked[address] -= BigInt(bn(d.amount));
            await pool.connect(d.user).unstake(i, bn(d.amount));
            count++;
            d.lockUntil = 0;
          }
        }
      }
      count++;
      // console.log("Tokens per block", (await pool.getConfig()).tokensPerBlock.toString());
      if (func < 15) {
        console.log(names[user.address], "stakes", amount, lockUntil);
        staked[user.address] += BigInt(bn(amount));
        if (staked[user.address] > maxStaked[user.address]) {
          maxStaked[user.address] = staked[user.address];
        }
        await lfg.connect(user).approve(pool.address, bn(amount));
        await pool.connect(user).stake(bn(amount), lockUntil);
        deposits[user.address].push({user, amount: amount, lockUntil: lockUntil});
      } else {
        console.log(names[user.address], "gets rewards");
        await pool.connect(user).processRewards();
      }
    }
    let dayPassed;
    while (blockNumber < endBlock) {
      dayPassed = Math.round((ts - ts0) / (3600 * 24));
      try {
        await randomAction();
      } catch (e) {
        console.log("Dead after", dayPassed, "days");
        console.error(e.message);
        failed = true;
        break;
      }
    }
    console.log("-------- RESULTS --------");
    let gains = {};
    let i = 0;
    for (let k in maxStaked) {
      gains[k] = (await formattedBalanceOf(users[i++])) - Number((maxStaked[k] /= 1000000000000000000n));
    }
    for (let a in maxStaked) {
      maxStaked[a] = Number(maxStaked[a] / 1000000000000000000n);
    }
    console.log("Max staked", maxStaked);
    console.log("Gain", gains);
    console.log("Total transactions", count);
    console.log("Remaining", await formattedBalanceOf(pool));
    expect(BigInt((await lfg.balanceOf(pool.address)).toString()) > 0n).to.be.true;
    expect(failed).to.be.false;
  });
});
