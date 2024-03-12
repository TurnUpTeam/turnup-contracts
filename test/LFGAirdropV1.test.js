const {ethers, upgrades} = require("hardhat");
const {expect} = require("chai");
const {toChecksumAddress} = require("ethereumjs-util");
const DeployUtils = require("eth-deploy-utils");

const {getTimestamp, increaseBlockTimestampBy} = require("./helpers");

describe("LFG Airdrop", function () {
  let lfg;
  let airdrop;
  let owner, bob, alice, fred, jim, jane, tokenHolder;
  let fundDestination;

  const addr0 = "0x" + "0".repeat(40);
  const deployUtils = new DeployUtils();

  before(async function () {
    [owner, bob, alice, fred, jim, jane, tokenHolder] = await ethers.getSigners();
    fundDestination = jane.address;
  });

  async function initAndDeploy() {
    airdrop = await deployUtils.deployProxy("LFGAirdropV1");

    let maxSupply = ethers.utils.parseEther("3000000000");
    let initialSupply = ethers.utils.parseEther("900000000");
    let amountReservedToPool = ethers.utils.parseEther("300000000");
    let amountReservedToSharesPool = ethers.utils.parseEther("200000000");
    lfg = await deployUtils.deployProxy(
      "LFGToken",
      tokenHolder.address,
      maxSupply,
      initialSupply,
      amountReservedToPool,
      amountReservedToSharesPool
    );
  }

  beforeEach(async function () {
    await initAndDeploy();
  });

  it("should be initialized with the correct parameter", async function () {
    expect(await airdrop.owner()).to.equal(owner.address);
    expect(await airdrop.lfg()).to.equal(addr0);
    expect(await airdrop.fundDestination()).to.equal(addr0);
    expect(await airdrop.maxLfgPerMember()).to.equal(0);
    expect(await airdrop.dropMemberAmount()).to.equal(0);
  });

  it("should be set lfg token", async function () {
    await airdrop.setLfgToken(lfg.address);
    expect(await airdrop.lfg()).to.equal(lfg.address);
  });

  it("should be set fund destination", async function () {
    await airdrop.setFundDestination(bob.address);
    expect(await airdrop.fundDestination()).to.equal(bob.address);
  });

  it("should be set max lfg per member", async function () {
    await airdrop.setMaxLfgPerMember(100);
    expect(await airdrop.maxLfgPerMember()).to.equal(100);
    await airdrop.setMaxLfgPerMember(99999);
    expect(await airdrop.maxLfgPerMember()).to.equal(99999);
  });

  it("should be airdrop with invalid parameter", async function () {
    await expect(airdrop.airdrop([], [])).to.be.revertedWith("InvalidParameter()");
    await expect(airdrop.airdrop([bob.address], [])).to.be.revertedWith("InvalidParameter()");
    await expect(airdrop.airdrop([], [100])).to.be.revertedWith("InvalidParameter()");
    await expect(airdrop.airdrop([bob.address], [100, 200])).to.be.revertedWith("InvalidParameter()");
    await expect(airdrop.airdrop([bob.address], [0])).to.be.revertedWith("InvalidLfgAmount()");
    await expect(airdrop.airdrop([addr0], [100])).to.be.revertedWith("InvalidParameter()");

    await airdrop.setLfgToken(lfg.address);

    await expect(airdrop.airdrop([bob.address], [100])).to.be.revertedWith("InvalidLfgAmount()");

    await airdrop.setMaxLfgPerMember(999999);
    await expect(airdrop.airdrop([bob.address], [100])).to.be.revertedWith("InsufficientLfg()");
  });

  it("should be airdrop with one user", async function () {
    lfg.connect(tokenHolder).transfer(airdrop.address, 10000);

    await airdrop.setLfgToken(lfg.address);
    await airdrop.setMaxLfgPerMember(1000);

    await airdrop.airdrop([bob.address], [100]);
    expect(await lfg.balanceOf(bob.address)).to.equal(100);
    expect(await lfg.balanceOf(airdrop.address)).to.equal(10000 - 100);

    expect(await airdrop.getAirdropAmount(bob.address)).to.equal(100);
    expect(await airdrop.getAirdropAmount(tokenHolder.address)).to.equal(0);

    expect(await airdrop.dropMemberAmount()).to.equal(1);
  });

  it("should be airdrop with two user", async function () {
    lfg.connect(tokenHolder).transfer(airdrop.address, 10000);

    await airdrop.setLfgToken(lfg.address);
    await airdrop.setMaxLfgPerMember(1000);

    await airdrop.airdrop([bob.address, alice.address], [100, 200]);
    expect(await lfg.balanceOf(bob.address)).to.equal(100);
    expect(await lfg.balanceOf(alice.address)).to.equal(200);
    expect(await lfg.balanceOf(airdrop.address)).to.equal(10000 - 100 - 200);

    expect(await airdrop.getAirdropAmount(bob.address)).to.equal(100);
    expect(await airdrop.getAirdropAmount(alice.address)).to.equal(200);
    expect(await airdrop.getAirdropAmount(tokenHolder.address)).to.equal(0);

    expect(await airdrop.dropMemberAmount()).to.equal(2);
  });

  it("should be airdrop with insufficient lfg 1", async function () {
    lfg.connect(tokenHolder).transfer(airdrop.address, 10000);

    await airdrop.setLfgToken(lfg.address);
    await airdrop.setMaxLfgPerMember(100000);

    await expect(airdrop.airdrop([bob.address], [10000 + 1])).to.be.revertedWith("InsufficientLfg()");

    expect(await lfg.balanceOf(airdrop.address)).to.equal(10000);
    expect(await airdrop.getAirdropAmount(bob.address)).to.equal(0);
    expect(await airdrop.dropMemberAmount()).to.equal(0);
  });

  it("should be airdrop with insufficient lfg 2", async function () {
    lfg.connect(tokenHolder).transfer(airdrop.address, 10000);

    await airdrop.setLfgToken(lfg.address);
    await airdrop.setMaxLfgPerMember(8000);

    await expect(airdrop.airdrop([bob.address, alice.address], [5000, 6000])).to.be.revertedWith("InsufficientLfg()");

    expect(await lfg.balanceOf(airdrop.address)).to.equal(10000);
    expect(await airdrop.getAirdropAmount(bob.address)).to.equal(0);
    expect(await airdrop.getAirdropAmount(alice.address)).to.equal(0);
    expect(await airdrop.dropMemberAmount()).to.equal(0);
  });

  it("should be airdrop with insufficient lfg 3", async function () {
    lfg.connect(tokenHolder).transfer(airdrop.address, 1000000);

    await airdrop.setLfgToken(lfg.address);
    await airdrop.setMaxLfgPerMember(8000);

    await expect(airdrop.airdrop([bob.address, alice.address], [5000, 10000])).to.be.revertedWith("InvalidLfgAmount()");

    expect(await lfg.balanceOf(airdrop.address)).to.equal(1000000);
    expect(await airdrop.getAirdropAmount(bob.address)).to.equal(0);
    expect(await airdrop.getAirdropAmount(alice.address)).to.equal(0);
    expect(await airdrop.dropMemberAmount()).to.equal(0);
  });

  it("should be airdrop duplicate", async function () {
    lfg.connect(tokenHolder).transfer(airdrop.address, 1000000);

    await airdrop.setLfgToken(lfg.address);
    await airdrop.setMaxLfgPerMember(8000);

    await airdrop.airdrop([bob.address], [100]);
    await airdrop.airdrop([bob.address, alice.address], [200, 200]);

    expect(await lfg.balanceOf(bob.address)).to.equal(100);
    expect(await lfg.balanceOf(alice.address)).to.equal(200);
  });

  it("should be batch get airdrop amount", async function () {
    lfg.connect(tokenHolder).transfer(airdrop.address, 1000000);

    await airdrop.setLfgToken(lfg.address);
    await airdrop.setMaxLfgPerMember(8000);

    await airdrop.airdrop([bob.address, alice.address], [100, 200]);

    amounts = await airdrop.batchGetAirdropAmount([bob.address, alice.address]);
    expect(amounts[0]).to.equal(100);
    expect(amounts[1]).to.equal(200);

    amounts = await airdrop.batchGetAirdropAmount([bob.address, alice.address, fred.address]);
    expect(amounts[0]).to.equal(100);
    expect(amounts[1]).to.equal(200);
    expect(amounts[2]).to.equal(0);
  });

  it("should be withdraw funds with invalid parameter", async function () {
    lfg.connect(tokenHolder).transfer(airdrop.address, 10000);

    await airdrop.setLfgToken(lfg.address);
    await expect(airdrop.withdrawFunds(1000)).to.be.revertedWith("ZeroFundDestination()");

    await airdrop.setFundDestination(fundDestination);
    await expect(airdrop.withdrawFunds(10000 + 1)).to.be.revertedWith("InvalidParameter()");
  });

  it("should be withdraw funds all", async function () {
    lfg.connect(tokenHolder).transfer(airdrop.address, 10000);

    await airdrop.setLfgToken(lfg.address);
    await airdrop.setFundDestination(fundDestination);

    await airdrop.withdrawFunds(0);

    expect(await lfg.balanceOf(airdrop.address)).to.equal(0);
    expect(await lfg.balanceOf(fundDestination)).to.equal(10000);
  });

  it("should be withdraw funds some", async function () {
    lfg.connect(tokenHolder).transfer(airdrop.address, 10000);

    await airdrop.setLfgToken(lfg.address);
    await airdrop.setFundDestination(fundDestination);

    await airdrop.withdrawFunds(1000);
    expect(await lfg.balanceOf(airdrop.address)).to.equal(10000 - 1000);
    expect(await lfg.balanceOf(fundDestination)).to.equal(1000);

    await airdrop.withdrawFunds(2000);
    expect(await lfg.balanceOf(airdrop.address)).to.equal(10000 - 1000 - 2000);
    expect(await lfg.balanceOf(fundDestination)).to.equal(1000 + 2000);
  });
});
