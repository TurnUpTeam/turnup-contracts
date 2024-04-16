const {ethers, upgrades} = require("hardhat");
const {expect} = require("chai"); 
const DeployUtils = require("eth-deploy-utils");
  
describe("NFTShares", function () {
  let oneEther;
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
    oneEther = ethers.utils.parseEther("1")

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

    for (let i = 0; i < 500; i += 23) {
      expect(await shares.isActive(bob.address, i)).to.be.false;
      expect(await shares.getSupply(bob.address, i)).to.equal(0);
      expect(await shares.balanceOf(bob.address, i, alice.address)).to.equal(0);
    }
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

  it("should be get protocol fee", async function () {
    let feePercent = await shares.protocolFeePercent()
    let one = ethers.utils.parseEther("1");
    let priceArr = ["0", "0.00", "0.01", "0.9888", "1", "1.5", "1.999", "1200", "100080001", "999999999"]
    for (let p in priceArr) {
      let price = ethers.utils.parseEther(p);
      expect(await shares.getProtocolFee(price)).to.equal(price.mul(feePercent).div(one));
    }
  });

  it("should be get subject fee", async function () {
    let feePercent = await shares.subjectFeePercent()
    let one = ethers.utils.parseEther("1");
    let priceArr = ["0", "0.00", "0.01", "0.9888", "1", "1.5", "1.999", "1200", "100080001", "999999999"]
    for (let p in priceArr) {
      let price = ethers.utils.parseEther(p);
      expect(await shares.getSubjectFee(price)).to.equal(price.mul(feePercent).div(one));
    }
  });

  it("should be get price", async function () {
    for (let i = 0; i < 10000; i += 33) {
      expect(await shares.getPrice(i, 1)).to.equal(oneEther.mul((i + 1) * (i + 1) * 5));
    }
    let supplyList = [0, 1, 3, 7, 13, 32, 57, 60, 82, 100, 160, 200, 230, 190, 330, 550, 700, 870, 960, 1060, 2030, 5000];
    let amountList = [1, 3, 6, 9, 12, 19, 26, 37, 49, 80, 99, 100];
    for (let i = 0; i < supplyList.length; i++) {
      for (let j = 0; j < amountList.length; j++) {
        let s = supplyList[i];
        let a = amountList[j];
        let expectSum = ethers.utils.parseEther("0");
        for (let k = 0; k < a; k++) {
          let p = oneEther.mul((s + 1 + k) * (s + 1 + k) * 5)
          expectSum = expectSum.add(p)
        }
        let actualSum = await shares.getPrice(s, a);
        expect(actualSum).to.equal(expectSum);
      }
    }
  });

  it("should be get buy price for supply 0", async function () {

  });

});
