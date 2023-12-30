const {ethers, upgrades} = require("hardhat");
const {expect} = require("chai");
const {toChecksumAddress} = require("ethereumjs-util");

const DeployUtils = require("eth-deploy-utils");

let counter = 1;
function cl(...args) {
  console.log("\n  >>>>", counter++, ...args, "\n");
}

function makePseudoAddress(address) {
  return toChecksumAddress("0x00000000000000" + address.slice(16));
}

describe("TurnupSharesV3", function () {
  let turnupShares;
  let owner;
  let project;
  let buyer, buyer2, buyer3, wished, wished1, wished2, operator, dao, beneficiary, subject, sub0, sub1, sub2;

  const addr0 = "0x" + "0".repeat(40);

  const deployUtils = new DeployUtils();

  async function increaseBlockTimestampBy(offset) {
    await this.ethers.provider.send("evm_increaseTime", [offset]);
    await this.ethers.provider.send("evm_mine");
  }

  before(async function () {
    [owner, project, buyer, buyer2, buyer3, subject2, subject] = await ethers.getSigners();
  });

  beforeEach(async function () {
    turnupShares = await deployUtils.deployProxy("TurnupSharesV3");
    await upgrades.upgradeProxy(turnupShares.address, await ethers.getContractFactory("TurnupSharesV3Pausable"));
    turnupShares = await ethers.getContractAt("TurnupSharesV3Pausable", turnupShares.address);
    expect(await turnupShares.getVer()).to.equal("v3.0.11");
  });

  async function init() {
    await turnupShares.setFeeDestination(project.address);
    const protocolFee = ethers.utils.parseUnits("50000000", "gwei"); // example fee
    await turnupShares.setProtocolFeePercent(protocolFee);
    const subjectFee = ethers.utils.parseUnits("50000000", "gwei"); // example fee
    await turnupShares.setSubjectFeePercent(subjectFee);
  }

  async function executeAndReturnGasCost(call) {
    const tx = await call;
    const receipt = await tx.wait(); // Wait for transaction to be mined to get the receipt
    const gasUsed = receipt.gasUsed;
    const txDetails = await ethers.provider.getTransaction(receipt.transactionHash);
    return gasUsed.mul(txDetails.gasPrice);
  }

  it("should block users from buying and selling shares when paused", async function () {
    await init();

    // owner buys keys
    const subjectKeyAmount = 4;

    const contractBalanceBefore = await ethers.provider.getBalance(turnupShares.address);
    expect(contractBalanceBefore).to.equal(0);

    let price = await turnupShares.getBuyPriceAfterFee(subject.address, 1);

    await turnupShares.connect(subject).buyShares(subject.address, 1, {value: price});

    price = await turnupShares.getBuyPriceAfterFee(subject.address, 2);

    await turnupShares.connect(buyer).buyShares(subject.address, 2, {value: price});

    await turnupShares.pause();

    await expect(turnupShares.connect(buyer).buyShares(subject.address, 1, {value: price})).to.be.revertedWith(
      "has been paused"
    );

    await turnupShares.unpause();

    await turnupShares.connect(buyer).sellShares(subject.address, 1);

    await expect(turnupShares.withdrawRemain()).to.be.revertedWith("not paused and locked");

    await turnupShares.lock();

    await expect(turnupShares.connect(buyer).sellShares(subject.address, 1)).to.be.revertedWith("has been paused");

    await expect(turnupShares.unpause()).to.be.revertedWith("Contract is locked");

    await turnupShares.withdrawRemain();
  });
});
