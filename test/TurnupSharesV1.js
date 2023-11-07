const {time, loadFixture} = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const {anyValue} = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const {expect} = require("chai");
const web3 = require("web3");

describe("TurnupSharesV1", function () {
  let zeroAddress = "0x0000000000000000000000000000000000000000";

  // We define a fixture to reuse the same setup in every test.
  // We use loadFixture to run this setup once, snapshot that state,
  // and reset Hardhat Network to that snapshot in every test.
  async function deployTurnupFixture() {
    // Contracts are deployed using the first signer/account by default
    const [owner, otherAccount] = await ethers.getSigners();

    const Turnup = await ethers.getContractFactory("TurnupSharesV1");
    const turnup = await Turnup.deploy();

    return {turnup, owner, otherAccount};
  }

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      const {turnup, owner, otherAccount} = await loadFixture(deployTurnupFixture);
      // console.log(await badass.owner())
      // console.log(owner.address)
      // console.log(otherAccount.address)
      expect(await turnup.owner()).to.equal(owner.address);
      expect(await turnup.owner()).to.not.equal(otherAccount.address);
    });

    it("renounceOwnership:Not should revert", async function () {
      const {turnup, owner, otherAccount} = await loadFixture(deployTurnupFixture);
      // await expect(badass.renounceOwnership()).not.to.be.reverted;
      await expect(turnup.renounceOwnership()).to.emit(turnup, "OwnershipTransferred");
      // await expect(badass.renounceOwnership()).not.to.be.reverted;
      expect(await turnup.owner()).to.not.equal(owner.address);
      expect(await turnup.owner()).to.not.equal(otherAccount.address);
      expect(await turnup.owner()).to.equal(zeroAddress);
    });

    it("renounceOwnership:Should revert with  Ownable: caller is not the owner", async function () {
      const {turnup, owner, otherAccount} = await loadFixture(deployTurnupFixture);
      await expect(turnup.connect(otherAccount).renounceOwnership()).to.be.revertedWith("Ownable: caller is not the owner");
    });

    it("transferOwnership", async function () {
      const {turnup, owner, otherAccount} = await loadFixture(deployTurnupFixture);
      // await expect(badass.renounceOwnership()).not.to.be.reverted;
      await expect(turnup.transferOwnership(otherAccount.address)).to.emit(turnup, "OwnershipTransferred");
      // await expect(badass.renounceOwnership()).not.to.be.reverted;
      expect(await turnup.owner()).to.not.equal(owner.address);
      expect(await turnup.owner()).to.equal(otherAccount.address);
      expect(await turnup.owner()).to.not.equal(zeroAddress);
    });

    it("transferOwnership:Should revert with  Ownable: caller is not the owner", async function () {
      const {turnup, owner, otherAccount} = await loadFixture(deployTurnupFixture);
      await expect(turnup.connect(otherAccount).transferOwnership(owner)).to.be.revertedWith(
        "Ownable: caller is not the owner"
      );
      expect(await turnup.owner()).to.equal(owner.address);
      expect(await turnup.owner()).to.not.equal(otherAccount.address);
      expect(await turnup.owner()).to.not.equal(zeroAddress);
    });
  });

  describe("setFeeDestination", function () {
    it("setFeeDestination:Should revert with  Ownable: caller is not the owner", async function () {
      const {turnup, owner, otherAccount} = await loadFixture(deployTurnupFixture);
      await expect(turnup.connect(otherAccount).setFeeDestination(owner)).to.be.revertedWith(
        "Ownable: caller is not the owner"
      );
      expect(await turnup.protocolFeeDestination()).to.not.equal(owner.address);
      expect(await turnup.protocolFeeDestination()).to.not.equal(otherAccount.address);
      expect(await turnup.protocolFeeDestination()).to.equal(zeroAddress);
    });

    it("setFeeDestination ok", async function () {
      const {turnup, owner, otherAccount} = await loadFixture(deployTurnupFixture);
      await expect(turnup.setFeeDestination(otherAccount)).not.to.be.reverted;
      expect(await turnup.protocolFeeDestination()).to.not.equal(owner.address);
      expect(await turnup.protocolFeeDestination()).to.equal(otherAccount.address);
      expect(await turnup.protocolFeeDestination()).to.not.equal(zeroAddress);
    });
  });

  describe("setProtocolFeePercent", function () {
    it("setProtocolFeePercent ok", async function () {
      const {turnup, owner, otherAccount} = await loadFixture(deployTurnupFixture);
      percent = web3.utils.toWei("0.5", "ether");
      await expect(turnup.setProtocolFeePercent(percent)).not.to.be.reverted;
      expect(await turnup.protocolFeePercent()).to.equal(percent);
    });

    it("setProtocolFeePercent:Should revert with  Ownable: caller is not the owner", async function () {
      const {turnup, owner, otherAccount} = await loadFixture(deployTurnupFixture);
      percent = web3.utils.toWei("0.5", "ether");
      zero = web3.utils.toWei("0", "ether");
      await expect(turnup.connect(otherAccount).setProtocolFeePercent(percent)).to.be.revertedWith(
        "Ownable: caller is not the owner"
      );
      expect(await turnup.protocolFeePercent()).to.equal(zero);
    });
  });

  describe("setSubjectFeePercent", function () {
    it("setSubjectFeePercent ok", async function () {
      const {turnup, owner, otherAccount} = await loadFixture(deployTurnupFixture);
      percent = web3.utils.toWei("0.5", "ether");
      await expect(turnup.setSubjectFeePercent(percent)).not.to.be.reverted;
      expect(await turnup.subjectFeePercent()).to.equal(percent);
    });

    it("setSubjectFeePercent:Should revert with  Ownable: caller is not the owner", async function () {
      const {turnup, owner, otherAccount} = await loadFixture(deployTurnupFixture);
      percent = web3.utils.toWei("0.5", "ether");
      zero = web3.utils.toWei("0", "ether");
      await expect(turnup.connect(otherAccount).setSubjectFeePercent(percent)).to.be.revertedWith(
        "Ownable: caller is not the owner"
      );
      expect(await turnup.subjectFeePercent()).to.equal(zero);
    });
  });

  describe("Price", function () {
    it("getPrice ok", async function () {
      const {turnup, owner} = await loadFixture(deployTurnupFixture);
      expect(await turnup.getPrice("0", "1")).to.equal(0);
    });
    it("getPrice ok", async function () {
      const {turnup, owner} = await loadFixture(deployTurnupFixture);
      expect(await turnup.getPrice("1", "1")).to.not.equal(0);
    });

    it("getBuyPrice ok", async function () {
      const {turnup, owner} = await loadFixture(deployTurnupFixture);
      console.log(await turnup.getBuyPrice(owner, 2));
      expect(await turnup.getBuyPrice(owner, 1)).to.equal(0);
    });

    /*
    it("getSellPrice ok", async function () {
      const { turnup, owner } = await loadFixture(deployTurnupFixture); 
      expect(await turnup.getSellPrice(owner, "1")).to.equal(0);
    });  
    */
  });
});
