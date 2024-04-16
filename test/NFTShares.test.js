const {ethers, upgrades} = require("hardhat");
const {expect} = require("chai"); 
const DeployUtils = require("eth-deploy-utils");
  
describe("NFTShares", function () {
  let lfg;
  let shares;
  let owner, bob, alice, fred, jim, jane, tokenHolder;
  let protocolFeeDestination;

  const addr0 = "0x" + "0".repeat(40);
  const deployUtils = new DeployUtils();

  before(async function () {
    [owner, bob, alice, fred, jim, jane, tokenHolder, protocolFeeDestination] = await ethers.getSigners();
  });

  async function initAndDeploy() {
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

    shares = await deployUtils.deployProxy("NFTShares", protocolFeeDestination.address, lfg.address);
  }

  beforeEach(async function () {
    await initAndDeploy();
  });

  it("should be initialized with the correct parameter", async function () {
    expect(await shares.owner()).to.equal(owner.address);
    expect(await shares.lfg()).to.equal(lfg.address);
    expect(await shares.protocolFeeDestination()).to.equal(protocolFeeDestination.address);
    expect(await shares.protocolFees()).to.equal(0);

    let feePercent = ethers.utils.parseEther("0.05")
    expect(await shares.protocolFeePercent()).to.equal(feePercent);
    expect(await shares.subjectFeePercent()).to.equal(feePercent);
  });
 
  it("should net set called by not owner", async function () {
    let feePercent = ethers.utils.parseEther("0.1");
    let newShares = shares.connect(bob)
    await expect(newShares.setSubjectFeePercent(feePercent)).to.be.revertedWith("Ownable: caller is not the owner"); 
    await expect(newShares.setProtocolFeePercent(feePercent)).to.be.revertedWith("Ownable: caller is not the owner"); 
    await expect(newShares.setProtocolFeeDestination(bob.address)).to.be.revertedWith("Ownable: caller is not the owner"); 
    await expect(newShares.setLFGToken(addr0)).to.be.revertedWith("Ownable: caller is not the owner"); 
  });

  it("should be set subject fee precent", async function () {
    let oldFeePercent = await shares.subjectFeePercent();
    let newFeePercent = ethers.utils.parseEther("0.1");
    await expect(shares.setSubjectFeePercent(newFeePercent))
      .to.emit(shares, "SubjectFeePercentUpdate")
      .withArgs(newFeePercent);
    expect(await shares.subjectFeePercent()).to.equal(newFeePercent);
    expect(await shares.subjectFeePercent()).not.to.equal(oldFeePercent);  
  });
  
  it("should be set protocol fee precent", async function () {
    let oldFeePercent = await shares.protocolFeePercent();
    let newFeePercent = ethers.utils.parseEther("0.1");
    await expect(shares.setProtocolFeePercent(newFeePercent))
      .to.emit(shares, "ProtocolFeePercentUpdate")
      .withArgs(newFeePercent);
    expect(await shares.protocolFeePercent()).to.equal(newFeePercent);
    expect(await shares.protocolFeePercent()).not.to.equal(oldFeePercent);  
  });

  it("should be set protocol fee destination", async function () {
    await expect(shares.setProtocolFeeDestination(bob.address))
    .to.emit(shares, "ProtocolFeeDestinationUpdate")
    .withArgs(bob.address);
  });

  it("should be set lfg token", async function () {
    await expect(shares.setLFGToken(bob.address))
    .to.emit(shares, "LFGTokenUpdate")
    .withArgs(bob.address);
  });
});
