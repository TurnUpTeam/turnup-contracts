const {expect} = require("chai");
const EthDeployUtils = require("eth-deploy-utils");

const deployUtils = new EthDeployUtils();

const {getTimestamp, increaseBlockTimestampBy, getBlockNumber} = require("./helpers");
const {ethers} = require("hardhat");
const {max} = require("hardhat/internal/util/bigint");

// To launch this test, move from .skip to .only
// It can take more than one minute to complete, depending on the machine.
describe.skip("CorePool Simulation Test", function () {
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

  async function increaseBlocksBy(seconds) {
    let blockNumber = (await pool.blockNumber()).toNumber();
    // console.log("increasing blocks by", seconds, "seconds, and", Math.floor(blocksPerDay * (seconds / 86400)), "blocks.");
    await increaseBlockTimestampBy(seconds);
    let newBlockNumber = blockNumber + Math.floor((blocksPerDay * seconds) / 86400);
    await pool.setFakeBlockNumber(newBlockNumber);
    return newBlockNumber;
  }

  async function formatBalance(b) {
    b = ethers.utils.formatEther(b);
    return Math.round(parseFloat(b) * 100) / 100;
  }

  async function formattedBalanceOf(user) {
    return formatBalance(await lfg.balanceOf(user.address));
  }

  it("should simulate the entire history of the pool", async function () {
    this.timeout(300000);
    let deposits = {};
    let users = [bob, alice, fred, jim, red, lee, jane, pippo, john, valery, august, marcel, gael, frankie, robert, will];
    let names = {};
    names[bob.address] = "bob";
    names[alice.address] = "alice";
    names[fred.address] = "fred";
    names[jim.address] = "jim";
    names[red.address] = "red";
    names[lee.address] = "lee";
    names[jane.address] = "jane";
    names[pippo.address] = "pippo";
    names[john.address] = "john";
    names[valery.address] = "valery";
    names[august.address] = "august";
    names[marcel.address] = "marcel";
    names[gael.address] = "gael";
    names[frankie.address] = "frankie";
    names[robert.address] = "robert";
    names[will.address] = "will";
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
    let j = 0;

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
            console.debug(names[address], "unstakes", d.amount);
            staked[address] -= BigInt(bn(d.amount));
            await pool.connect(d.user).unstake(i, bn(d.amount));
            count++;
            d.lockUntil = 0;
          }
        }
      }
      count++;
      if (func < 15) {
        console.debug(names[user.address], "stakes", amount, lockUntil);
        staked[user.address] += BigInt(bn(amount));
        if (staked[user.address] > maxStaked[user.address]) {
          maxStaked[user.address] = staked[user.address];
        }
        await lfg.connect(user).approve(pool.address, bn(amount));
        await pool.connect(user).stake(bn(amount), lockUntil);
        deposits[user.address].push({user, amount: amount, lockUntil: lockUntil});
      } else {
        console.debug(names[user.address], "gets rewards");
        await pool.connect(user).processRewards();
      }
    }

    let dayPassed;
    while (blockNumber < endBlock) {
      dayPassed = Math.round((ts - ts0) / (3600 * 24));
      try {
        await randomAction();
      } catch (e) {
        console.debug("Dead after", dayPassed, "days");
        console.error(e.message);
        failed = true;
        break;
      }
      // if (j++ > 1000) break;
    }
    console.debug("\n-------- RESULTS --------");
    console.debug("Max staked and gains:");
    let i = 0;
    for (let a in maxStaked) {
      console.debug(
        names[a],
        Number(maxStaked[a] / 1000000000000000000n),
        Math.round((await formattedBalanceOf(users[i++])) - Number((maxStaked[a] /= 1000000000000000000n)))
      );
    }
    console.debug("\nTotal transactions:", count);
    console.debug("LFG balance of the pool", await formattedBalanceOf(pool));
    expect(BigInt((await lfg.balanceOf(pool.address)).toString()) > 0n).to.be.true;
    expect(failed).to.be.false;
  });
});
