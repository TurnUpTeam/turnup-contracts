const {ethers, network} = require("hardhat");
const {expect} = require("chai");
const {anyValue} = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const DeployUtils = require("eth-deploy-utils");

describe.only("Meme", function () {
  let zeroEther, oneEther, millionEther, tooManyEther;
  let chainId;
  let owner, bob, alice, fred, jim, jane, tokenHolder;
  let protocolFeeDestination;
  let lfg;
  let memeFactory;
  let memeImplementation;
  let mirrorImplementation;
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
    mirrorImplementation = await deployUtils.deploy("Meme404Mirror", addr0);

    memeFactory = await deployUtils.deployProxy(
      "MemeFactory",
      protocolFeeDestination.address,
      [bob.address],
      memeImplementation.address,
      mirrorImplementation.address,
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

    expect(await memeFactory.memeImplementation()).to.equal(memeImplementation.address);
    expect(await memeFactory.mirrorImplementation()).to.equal(mirrorImplementation.address);
  });

  it("should be update LFGToken", async function () {
    expect(await memeFactory.lfgToken()).to.equal(addr0);
    await expect(memeFactory.setLFGToken(lfg.address)).to.emit(memeFactory, "LfgTokenUpdate").withArgs(lfg.address);
    expect(await memeFactory.lfgToken()).to.equal(lfg.address);
    await expect(memeFactory.connect(bob).setLFGToken(lfg.address)).to.be.revertedWith("Ownable: caller is not the owner");
  });

  it("should be update subject fee percent", async function () {
    expect(await memeFactory.subjectFeePercent()).to.equal(0);
    let percent = ethers.utils.parseEther("0.53");
    await expect(memeFactory.setSubjectFeePercent(percent)).to.emit(memeFactory, "SubjectFeePercentUpdate").withArgs(percent);
    expect(await memeFactory.subjectFeePercent()).to.equal(percent);

    await expect(memeFactory.connect(bob).setSubjectFeePercent(percent)).to.be.revertedWith("Ownable: caller is not the owner");
  });

  it("should be update protocol fee percent", async function () {
    let defaultPercent = ethers.utils.parseEther("0.05");
    expect(await memeFactory.protocolFeePercent()).to.equal(defaultPercent);
    let percent = ethers.utils.parseEther("0.53");
    await expect(memeFactory.setProtocolFeePercent(percent)).to.emit(memeFactory, "ProtocolFeePercentUpdate").withArgs(percent);
    expect(await memeFactory.protocolFeePercent()).to.equal(percent);

    await expect(memeFactory.connect(bob).setProtocolFeePercent(percent)).to.be.revertedWith("Ownable: caller is not the owner");
  });

  it("should be update protocol fee destination", async function () { 
    expect(await memeFactory.protocolFeeDestination()).to.equal(protocolFeeDestination.address); 
    await expect(memeFactory.setProtocolFeeDestination(bob.address)).to.emit(memeFactory, "ProtocolFeeDestinationUpdate").withArgs(bob.address);
    expect(await memeFactory.protocolFeeDestination()).to.equal(bob.address);

    await expect(memeFactory.connect(bob).setProtocolFeePercent(bob.address)).to.be.revertedWith("Ownable: caller is not the owner");
  });

  function toBn(v) {
    return ethers.BigNumber.from(v);
  }

  it("should be getPrice(Linear)", async function () {
    let priceType = 1;
    let arg1 = ethers.utils.parseEther("5");
    let arg2 = ethers.utils.parseEther("1");

    let amountArr = [1, 2, 3, 4, 5]
    let expectedPriceArr = [6, 17, 33, 54, 80] 
    for (var i = 0; i < amountArr.length; i++) {
      let expectedPrice = ethers.utils.parseEther(expectedPriceArr[i].toString())
      expect(await memeFactory.getPrice(0, amountArr[i], priceType, arg1, arg2)).to.equal(expectedPrice);
    } 

    amountArr = [1, 2, 3, 4]
    expectedPriceArr = [16, 37, 63, 94] 
    for (var i = 0; i < amountArr.length; i++) {
      let expectedPrice = ethers.utils.parseEther(expectedPriceArr[i].toString())
      expect(await memeFactory.getPrice(2, amountArr[i], priceType, arg1, arg2)).to.equal(expectedPrice);
    } 
  });

  it("should be getPrice(QuadCurve)", async function () { 
    let priceType = 2;  
    let arg1 = ethers.utils.parseEther("5");
    let arg2 = ethers.utils.parseEther("2");
 
    let amountArr = [1, 2, 3, 4, 5]
    let expectedPriceArr = [7, 31, 82, 170, 305] 
    for (var i = 0; i < amountArr.length; i++) {
      let expectedPrice = ethers.utils.parseEther(expectedPriceArr[i].toString())
      expect(await memeFactory.getPrice(0, amountArr[i], priceType, arg1, arg2)).to.equal(expectedPrice);
    } 

    amountArr = [1, 2, 3, 4]
    expectedPriceArr = [51, 139, 274, 466] 
    for (var i = 0; i < amountArr.length; i++) {
      let expectedPrice = ethers.utils.parseEther(expectedPriceArr[i].toString())
      expect(await memeFactory.getPrice(2, amountArr[i], priceType, arg1, arg2)).to.equal(expectedPrice);
    } 
  });

  it("should be getPrice(Fixed)", async function () {
    let priceType = 3;
    let arg1 = ethers.utils.parseEther("5"); 
    let arg2 = ethers.utils.parseEther("0");

    let amountArr = [1, 2, 3, 4, 5]
    let expectedPriceArr = [5, 10, 15, 20, 25] 
    for (var i = 0; i < amountArr.length; i++) {
      let expectedPrice = ethers.utils.parseEther(expectedPriceArr[i].toString())
      expect(await memeFactory.getPrice(0, amountArr[i], priceType, arg1, arg2)).to.equal(expectedPrice);
    } 

    amountArr = [1, 2, 3, 4]
    expectedPriceArr = [5, 10, 15, 20] 
    for (var i = 0; i < amountArr.length; i++) {
      let expectedPrice = ethers.utils.parseEther(expectedPriceArr[i].toString())
      expect(await memeFactory.getPrice(2, amountArr[i], priceType, arg1, arg2)).to.equal(expectedPrice);
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
