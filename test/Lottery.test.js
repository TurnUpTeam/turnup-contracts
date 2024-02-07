const {ethers, upgrades} = require("hardhat");
const {expect} = require("chai");
const {toChecksumAddress} = require("ethereumjs-util");
const DeployUtils = require("eth-deploy-utils");

const {getTimestamp, increaseBlockTimestampBy} = require("./helpers");

describe("Lottery", function () {
  let lottery;
  let owner,bob;
  
  const deployUtils = new DeployUtils();
 
  let minLfgPerPick = ethers.utils.parseEther("100");
  let minMaticPerPick = ethers.utils.parseEther("0.1");
  let redPackLifeTime = 24 * 3600;   // 1 day
  let maxStartTime = 24 * 3600; // 1 day
  let protocolFeePercent = ethers.utils.parseEther("0.01");
  let protocolFeeDestination;

  before(async function () {
    [
      owner,
      bob, 
    ] = await ethers.getSigners();
    protocolFeeDestination = owner.address;
  });

  async function initAndDeploy() { 
    lottery = await await deployUtils.deployProxy(
      "Lottery",
      minLfgPerPick,
      minMaticPerPick,
      redPackLifeTime,
      maxStartTime,
      protocolFeePercent,
      protocolFeeDestination,
    );
  }

  beforeEach(async function () {
    await initAndDeploy();
  });

  it("should be initialized with the correct parameter", async function () {
    expect(await lottery.owner()).to.equal(owner.address);
    expect(await lottery.minLfgPerPick()).to.equal(minLfgPerPick);
    expect(await lottery.minMaticPerPick()).to.equal(minMaticPerPick);
    expect(await lottery.redPackLifeTime()).to.equal(redPackLifeTime);
    expect(await lottery.maxStartTime()).to.equal(maxStartTime);
    expect(await lottery.protocolFeePercent()).to.equal(protocolFeePercent);
    expect(await lottery.protocolFeeDestination()).to.equal(protocolFeeDestination);
    expect(await lottery.lfgProtocolFees()).to.equal(0);
    expect(await lottery.maticProtocolFees()).to.equal(0);
  });

  it("should be set lfg token address", async function () {
    await lottery.setLFGToken(bob);
    expect(await lottery.lfg()).to.equal(bob);
    await expect(lottery.setLFGToken(bob)).revertedWith("InvalidNoZeroLfg");
  });

  it("should be set shares address", async function () {
    await lottery.setShares(bob);
    expect(await lottery.shares()).to.equal(bob);
    await expect(lottery.setShares(bob)).revertedWith("InvalidNoZeroLfg");
  });
 
});
