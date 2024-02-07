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
 

  it("should be initialized with the correct owner", async function () {
    expect(await lottery.owner()).to.equal(owner.address);
  });
 
});
