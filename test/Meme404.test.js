const {ethers, network} = require("hardhat");
const {expect} = require("chai");
const {anyValue} = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const DeployUtils = require("eth-deploy-utils");

describe("Meme", function () {
  let zeroEther, oneEther, millionEther, tooManyEther;
  let chainId;
  let owner, bob, alice, fred, jim, jane, tokenHolder;
  let protocolFeeDestination;
  let lfg;
  let memeFactory;
  let memeImplementation;
  const addr0 = "0x" + "0".repeat(40);
  const deployUtils = new DeployUtils();

  before(async function () {
    [owner, bob, alice, fred, jim, jane, tokenHolder, protocolFeeDestination] = await ethers.getSigners();
    chainId = network.config.chainId;
  });

  async function initAndDeploy() {
    zeroEther = ethers.utils.parseEther("0");
    oneEther = ethers.utils.parseEther("1");
    millionEther = ethers.utils.parseEther("1000000");
    tooManyEther = ethers.utils.parseEther("100000000000");

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
    memeImplementation = await deployUtils.deploy("Meme404");

    memeFactory = await deployUtils.deployProxy(
      "Meme404Factory",
      protocolFeeDestination.address,
      [bob.address],
      memeImplementation.address
    );
  }

  beforeEach(async function () {
    await initAndDeploy();
  });

  it("should be initialized with the correct parameter", async function () {
    expect(await memeFactory.owner()).to.equal(owner.address);
    expect(await memeFactory.owner()).to.not.equal(bob.address);
    expect(await memeFactory.protocolFeeDestination()).to.equal(protocolFeeDestination.address);
    expect(await memeFactory.lfgToken()).to.equal(addr0);
    expect(await memeFactory.baseClubId()).to.equal(0);

    let feePercent = ethers.utils.parseEther("0.05");
    expect(await memeFactory.protocolFeePercent()).to.equal(feePercent);

    expect(await memeFactory.subjectFeePercent()).to.equal(0);
    expect(await memeFactory.protocolLFGFees()).to.equal(0);
    expect(await memeFactory.protocolNativeFees()).to.equal(0);
  });

  it("should be update LFGToken", async function () {
    expect(await memeFactory.lfgToken()).to.equal(addr0);
    await expect(memeFactory.setLFGToken(lfg.address)).to.emit(memeFactory, "LfgTokenUpdate").withArgs(lfg.address);
    expect(await memeFactory.lfgToken()).to.equal(lfg.address);
    await expect(memeFactory.connect(bob).setLFGToken(lfg.address)).to.be.revertedWith("Ownable: caller is not the owner");
  });

  function toBn(v) {
    return ethers.BigNumber.from(v);
  }

  it("should be getPrice", async function () {
    let quadCurveA = 5;
    let priceType = 1;
    let priceArgs = {quadCurveA: quadCurveA};

    for (let i = 0; i < 100; i += 5) {
      let expectedPrice = toBn((i + 1) * (i + 1))
        .mul(oneEther)
        .div(toBn(quadCurveA));
      expect(await memeFactory.getPrice(i, 1, priceType, priceArgs)).to.equal(expectedPrice);
    }

    for (let i = 0; i < 100; i += 5) {
      for (let amount in [1, 3, 5, 8, 12, 55, 99]) {
        let expectedPrice = toBn(0);
        for (let j = 0; j < amount; j++) {
          let price = toBn((i + 1 + j) * (i + 1 + j))
            .mul(oneEther)
            .div(toBn(quadCurveA));
          expectedPrice = expectedPrice.add(price);
        }
        expect(await memeFactory.getPrice(i, amount, priceType, priceArgs)).to.equal(expectedPrice);
      }
    }
  });

  it.skip("should be newMemeClubWithQuadCurve(check arguments)", async function () {
    await expect(memeFactory.newMemeClubWithQuadCurve(1, "name", "symbol", "tokenUri", false, 0)).to.be.revertedWith(
      "MemeClubLFGUnsupported()"
    );
    await expect(memeFactory.newMemeClubWithQuadCurve(1, "name", "symbol", "tokenUri", true, 0)).to.be.revertedWith(
      "MemeClubPriceArgs()"
    );
  });

  it.skip("should be newMemeClubWithQuadCurve($LFG)", async function () {
    await memeFactory.setLFGToken(lfg.address);
    let expectedClubId = chainId * 1000000 + 1;
    await expect(memeFactory.newMemeClubWithQuadCurve(1, "name", "symbol", "tokenUri", false, 10))
      .to.emit(memeFactory, "MemeClubCreated")
      .withArgs(1, expectedClubId, anyValue);
    await expect(memeFactory.connect(bob).newMemeClubWithQuadCurve(2, "name", "symbol", "tokenUri", false, 10))
      .to.emit(memeFactory, "MemeClubCreated")
      .withArgs(2, expectedClubId + 1, anyValue);

    let club = await memeFactory.getMemeClub(expectedClubId);
    expect(club.clubId).to.equal(expectedClubId);
    expect(club.isNative).to.be.false;
    expect(club.isLocked).to.be.false;
    expect(club.nftAddress).to.not.equal(addr0);
    expect(club.memeAddress).to.equal(addr0);
    expect(club.supply).to.equal(0);
    expect(club.funds).to.equal(0);
    expect(club.priceType).to.equal(1);
    expect(club.priceArgs.quadCurveA).to.equal(10);
  });

  it.skip("should be newMemeClubWithQuadCurve(Native)", async function () {
    let expectedClubId = chainId * 1000000 + 1;
    await expect(memeFactory.newMemeClubWithQuadCurve(1, "name", "symbol", "tokenUri", true, 10))
      .to.emit(memeFactory, "MemeClubCreated")
      .withArgs(1, expectedClubId, anyValue);
    await expect(memeFactory.newMemeClubWithQuadCurve(2, "name", "symbol", "tokenUri", true, 10))
      .to.emit(memeFactory, "MemeClubCreated")
      .withArgs(2, expectedClubId + 1, anyValue);

    let club = await memeFactory.getMemeClub(expectedClubId);
    expect(club.clubId).to.equal(expectedClubId);
    expect(club.isNative).to.be.true;
    expect(club.isLocked).to.be.false;
    expect(club.nftAddress).to.not.equal(addr0);
    expect(club.memeAddress).to.equal(addr0);
    expect(club.supply).to.equal(0);
    expect(club.funds).to.equal(0);
    expect(club.priceType).to.equal(1);
    expect(club.priceArgs.quadCurveA).to.equal(10);
  });

  function randBetween(min, max) {
    let diff = max - min;
    return Math.floor(min + diff * Math.random());
  }

  it.skip("should be buyCard (Native)", async function () {
    await expect(memeFactory.buyCard(0, 0, tooManyEther)).to.be.revertedWith("InvalidAmount()");
    await expect(memeFactory.buyCard(0, 1, tooManyEther)).to.be.revertedWith("MemeClubNotFound()");

    let quadCurveA = 1000000;
    let priceType = 1;
    let priceArgs = {quadCurveA: quadCurveA};

    let clubId = chainId * 1000000 + 1;
    await memeFactory.newMemeClubWithQuadCurve(1, "name", "symbol", "tokenUri", true, quadCurveA);

    await expect(memeFactory.buyCard(clubId, 1, zeroEther)).to.be.revertedWith("InsufficientFunds()");

    for (let i = 0; i < 5; i++) {
      let club = await memeFactory.getMemeClub(clubId);
      let supply = club.supply;
      let amount = randBetween(1, 10);
      let expectedPrice = toBn(0);
      for (let j = 0; j < amount; j++) {
        let price =
          supply.add(1 + j) *
          supply
            .add(1 + j)
            .mul(oneEther)
            .div(toBn(quadCurveA));
        expectedPrice = expectedPrice.add(price);
      }

      let actualPrice = await memeFactory.getPrice(supply, amount, priceType, priceArgs);
      expect(expectedPrice).to.equal(actualPrice);

      let balanceBefore = await ethers.provider.getBalance(owner.address);
      await expect(memeFactory.buyCard(clubId, amount, zeroEther, {value: expectedPrice})).to.emit(
        memeFactory,
        "MemeClubTrade"
      );
      let balanceAfter = await ethers.provider.getBalance(owner.address);
      expect(balanceBefore.gte(balanceAfter.add(expectedPrice))).to.be.true;

      expect(await memeFactory.ownerOf(club.nftAddress, i + 1)).to.equal(owner.address);
    }
  });

  it.skip("should be sellCard (Native)", async function () {
    let quadCurveA = 1000000;
    let priceType = 1;
    let priceArgs = {quadCurveA: quadCurveA};

    let clubId = chainId * 1000000 + 1;
    await memeFactory.newMemeClubWithQuadCurve(1, "name", "symbol", "tokenUri", true, quadCurveA);

    let actualPrice = await memeFactory.getPrice(0, 1, priceType, priceArgs);
    await expect(memeFactory.buyCard(clubId, 1, zeroEther, {value: actualPrice})).to.emit(memeFactory, "MemeClubTrade");

    let club = await memeFactory.getMemeClub(clubId);
    expect(club.funds).to.equal(actualPrice);
    expect(club.supply).to.equal(1);
    expect(await ethers.provider.getBalance(memeFactory.address)).to.equal(actualPrice);

    let tokenId = 1;
    expect(await memeFactory.ownerOf(club.nftAddress, tokenId)).to.equal(owner.address);

    await expect(memeFactory.sellCard(clubId, [tokenId])).to.emit(memeFactory, "MemeClubTrade");
    club = await memeFactory.getMemeClub(clubId);
    expect(club.funds).to.equal(0);
    expect(club.supply).to.equal(0);
    expect(await ethers.provider.getBalance(memeFactory.address)).to.equal(0);
  });

  it.skip("should be buyCard ($LFG)", async function () {
    let quadCurveA = 1000000;
    let priceType = 1;
    let priceArgs = {quadCurveA: quadCurveA};

    let clubId = chainId * 1000000 + 1;

    await memeFactory.setLFGToken(lfg.address);
    await memeFactory.newMemeClubWithQuadCurve(1, "name", "symbol", "tokenUri", false, quadCurveA);

    await expect(memeFactory.buyCard(clubId, 1, zeroEther, {value: oneEther})).to.be.revertedWith("InvalidFunds()");
    await expect(memeFactory.buyCard(clubId, 1, zeroEther)).to.be.revertedWith("InsufficientFunds()");
    await expect(memeFactory.buyCard(clubId, 1, tooManyEther)).to.be.revertedWith("InsufficientLFG()");

    await lfg.connect(owner).approve(memeFactory.address, tooManyEther);
    await lfg.connect(tokenHolder).transfer(owner.address, millionEther);

    for (let i = 0; i < 5; i++) {
      let club = await memeFactory.getMemeClub(clubId);
      let supply = club.supply;
      let amount = randBetween(1, 10);
      let expectedPrice = toBn(0);
      for (let j = 0; j < amount; j++) {
        let price =
          supply.add(1 + j) *
          supply
            .add(1 + j)
            .mul(oneEther)
            .div(toBn(quadCurveA));
        expectedPrice = expectedPrice.add(price);
      }

      let actualPrice = await memeFactory.getPrice(supply, amount, priceType, priceArgs);
      expect(expectedPrice).to.equal(actualPrice);

      let balanceBefore = await lfg.balanceOf(owner.address);
      await expect(memeFactory.buyCard(clubId, amount, expectedPrice)).to.emit(memeFactory, "MemeClubTrade");
      let balanceAfter = await lfg.balanceOf(owner.address);
      expect(balanceBefore.gte(balanceAfter.add(expectedPrice))).to.be.true;

      expect(await memeFactory.ownerOf(club.nftAddress, i + 1)).to.equal(owner.address);
    }
  });

  it.skip("should be sellCard (Native)", async function () {
    let quadCurveA = 1000000;
    let priceType = 1;
    let priceArgs = {quadCurveA: quadCurveA};

    let clubId = chainId * 1000000 + 1;

    await lfg.connect(owner).approve(memeFactory.address, tooManyEther);
    await lfg.connect(tokenHolder).transfer(owner.address, millionEther);

    await memeFactory.setLFGToken(lfg.address);
    await memeFactory.newMemeClubWithQuadCurve(1, "name", "symbol", "tokenUri", false, quadCurveA);

    let actualPrice = await memeFactory.getPrice(0, 1, priceType, priceArgs);
    await expect(memeFactory.buyCard(clubId, 1, actualPrice)).to.emit(memeFactory, "MemeClubTrade");

    let club = await memeFactory.getMemeClub(clubId);
    expect(club.funds).to.equal(actualPrice);
    expect(club.supply).to.equal(1);
    expect(await lfg.balanceOf(memeFactory.address)).to.equal(actualPrice);

    let tokenId = 1;
    expect(await memeFactory.ownerOf(club.nftAddress, tokenId)).to.equal(owner.address);

    await expect(memeFactory.sellCard(clubId, [tokenId])).to.emit(memeFactory, "MemeClubTrade");
    club = await memeFactory.getMemeClub(clubId);
    expect(club.funds).to.equal(0);
    expect(club.supply).to.equal(0);
    expect(await lfg.balanceOf(memeFactory.address)).to.equal(0);
  });

  it.skip("should be pause", async function () {
    let quadCurveA = 1000000;
    let priceType = 1;
    let priceArgs = {quadCurveA: quadCurveA};

    await expect(memeFactory.newMemeClubWithQuadCurve(1, "name", "symbol", "tokenUri", true, quadCurveA)).to.emit(
      memeFactory,
      "MemeClubCreated"
    );

    let actualPrice = await memeFactory.getPrice(0, 1, priceType, priceArgs);

    let clubId = chainId * 1000000 + 1;
    await expect(memeFactory.buyCard(clubId, 1, zeroEther, {value: actualPrice})).to.emit(memeFactory, "MemeClubTrade");
    await expect(memeFactory.sellCard(clubId, [1])).to.emit(memeFactory, "MemeClubTrade");

    await memeFactory.pause();

    await expect(memeFactory.newMemeClubWithQuadCurve(1, "name", "symbol", "tokenUri", true, quadCurveA)).to.be.revertedWith(
      "Pausable: paused"
    );
    await expect(memeFactory.buyCard(clubId, 1, zeroEther, {value: actualPrice})).to.be.revertedWith("Pausable: paused");
    await expect(memeFactory.sellCard(clubId, [1])).to.be.revertedWith("Pausable: paused");

    await memeFactory.unpause();
    await expect(memeFactory.buyCard(clubId, 1, zeroEther, {value: actualPrice})).to.emit(memeFactory, "MemeClubTrade");
    await expect(memeFactory.sellCard(clubId, [1])).to.emit(memeFactory, "MemeClubTrade");
  });
});
