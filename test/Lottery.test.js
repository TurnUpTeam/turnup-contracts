const {ethers, upgrades} = require("hardhat");
const {expect} = require("chai");
const {toChecksumAddress} = require("ethereumjs-util");
const DeployUtils = require("eth-deploy-utils");

const {getTimestamp, increaseBlockTimestampBy} = require("./helpers");

describe("Lottery", function () {
  let lottery;
  let shares;
  let owner,bob;
  
  const addr0 = "0x" + "0".repeat(40);
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
    // deploy shares
    shares = await deployUtils.deployProxy("TurnupSharesV4");
    await shares.setFeeDestination(owner.address)
    await shares.setProtocolFeePercent(ethers.utils.parseEther("0.05"))
    await shares.setSubjectFeePercent(ethers.utils.parseEther("0.05"))
    await shares.setOperator(owner.address, true);

    // deploy lfg token

    // deploy lottery
    lottery = await deployUtils.deployProxy(
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
    await lottery.setLFGToken(bob.address);
    expect(await lottery.lfg()).to.equal(bob.address);
    await expect(lottery.setLFGToken(bob.address)).revertedWith("InvalidNoZeroLfg");
  });

  it("should be set shares address", async function () {
    await lottery.setShares(bob.address);
    expect(await lottery.shares()).to.equal(bob.address);
    await expect(lottery.setShares(bob.address)).revertedWith("InvalidNoZeroShares");
  });

  it("should be set min lfg per pick", async function () {
    newValue = ethers.utils.parseEther("199");
    await lottery.updateMinLfgPerPick(newValue);
    expect(await lottery.minLfgPerPick()).to.equal(newValue);
  });

  it("should be set min lfg per pick", async function () {
    newValue = ethers.utils.parseEther("199");
    await lottery.updateMinMaticPerPick(newValue);
    expect(await lottery.minMaticPerPick()).to.equal(newValue);
  });

  it("should be set red pack life time", async function () {
    newValue = 2 * 24 * 3600;
    await lottery.updateRedPackLifeTime(newValue);
    expect(await lottery.redPackLifeTime()).to.equal(newValue);
  });

  it("should be set max start time", async function () {
    newValue = 2 * 24 * 3600;
    await lottery.updateMaxStartTime(newValue);
    expect(await lottery.maxStartTime()).to.equal(newValue);
  });
 
  it("should be set protocol fee percent", async function () { 
    newValue = ethers.utils.parseEther("0.15");
    await lottery.updateProtocolFeePercent(newValue);
    expect(await lottery.protocolFeePercent()).to.equal(newValue);
  });

  it("should be set protocol fee destination", async function () { 
    await lottery.updateProtocolFeeDestination(bob.address);
    expect(await lottery.protocolFeeDestination()).to.equal(bob.address);
  });

  it("should be not holder", async function () { 
    await lottery.setShares(shares.address); 
    expect(await lottery.isHolder(owner.address, bob.address)).to.be.false;
  });

  it("should be holder", async function () { 
    let subject = bob;
    let buyer = owner
    let price = await shares.getBuyPriceAfterFee(subject.address, 1);
    await shares.connect(buyer).buyShares(subject.address, 1, {value: price})
    
    await lottery.setShares(shares.address); 
    expect(await lottery.isHolder(subject.address, buyer.address)).to.be.true;
  });
});
