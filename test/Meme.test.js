const {ethers, network} = require("hardhat");
const {expect} = require("chai");
const {anyValue} = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const DeployUtils = require("eth-deploy-utils");

const {signPackedData, privateKeyByWallet} = require("./helpers");

describe.only("Meme", function () {
  let zeroEther, oneEther, millionEther, tooManyEther;
  let chainId;
  let owner, bob, alice, fred, tokenHolder, validator;
  let protocolFeeDestination;
  let lfg;
  let memeFactory;
  let memeImplementation;
  let mirrorImplementation;
  const addr0 = "0x" + "0".repeat(40);
  const deployUtils = new DeployUtils();

  before(async function () {
    [owner, bob, alice, fred, tokenHolder, protocolFeeDestination, validator] = await ethers.getSigners();
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
      [validator.address],
      memeImplementation.address,
      mirrorImplementation.address
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

    await expect(memeFactory.connect(bob).setProtocolFeePercent(percent)).to.be.revertedWith(
      "Ownable: caller is not the owner"
    );
  });

  it("should be update protocol fee destination", async function () {
    expect(await memeFactory.protocolFeeDestination()).to.equal(protocolFeeDestination.address);
    await expect(memeFactory.setProtocolFeeDestination(bob.address))
      .to.emit(memeFactory, "ProtocolFeeDestinationUpdate")
      .withArgs(bob.address);
    expect(await memeFactory.protocolFeeDestination()).to.equal(bob.address);

    await expect(memeFactory.connect(bob).setProtocolFeePercent(bob.address)).to.be.revertedWith(
      "Ownable: caller is not the owner"
    );
  });

  function toBn(v) {
    return ethers.BigNumber.from(v);
  }

  it("should be getPrice(Linear)", async function () {
    let priceType = 1;
    let arg1 = ethers.utils.parseEther("5");
    let arg2 = ethers.utils.parseEther("1");

    let amountArr = [1, 2, 3, 4, 5];
    let expectedPriceArr = [6, 17, 33, 54, 80];
    for (var i = 0; i < amountArr.length; i++) {
      let expectedPrice = ethers.utils.parseEther(expectedPriceArr[i].toString());
      expect(await memeFactory.getPrice(0, amountArr[i], priceType, arg1, arg2)).to.equal(expectedPrice);
    }

    amountArr = [1, 2, 3, 4];
    expectedPriceArr = [16, 37, 63, 94];
    for (var i = 0; i < amountArr.length; i++) {
      let expectedPrice = ethers.utils.parseEther(expectedPriceArr[i].toString());
      expect(await memeFactory.getPrice(2, amountArr[i], priceType, arg1, arg2)).to.equal(expectedPrice);
    }
  });

  it("should be getPrice(QuadCurve)", async function () {
    let priceType = 2;
    let arg1 = ethers.utils.parseEther("5");
    let arg2 = ethers.utils.parseEther("2");

    let amountArr = [1, 2, 3, 4, 5];
    let expectedPriceArr = [7, 31, 82, 170, 305];
    for (var i = 0; i < amountArr.length; i++) {
      let expectedPrice = ethers.utils.parseEther(expectedPriceArr[i].toString());
      expect(await memeFactory.getPrice(0, amountArr[i], priceType, arg1, arg2)).to.equal(expectedPrice);
    }

    amountArr = [1, 2, 3, 4];
    expectedPriceArr = [51, 139, 274, 466];
    for (var i = 0; i < amountArr.length; i++) {
      let expectedPrice = ethers.utils.parseEther(expectedPriceArr[i].toString());
      expect(await memeFactory.getPrice(2, amountArr[i], priceType, arg1, arg2)).to.equal(expectedPrice);
    }
  });

  it("should be getPrice(Fixed)", async function () {
    let priceType = 3;
    let arg1 = ethers.utils.parseEther("5");
    let arg2 = ethers.utils.parseEther("0");

    let amountArr = [1, 2, 3, 4, 5];
    let expectedPriceArr = [5, 10, 15, 20, 25];
    for (var i = 0; i < amountArr.length; i++) {
      let expectedPrice = ethers.utils.parseEther(expectedPriceArr[i].toString());
      expect(await memeFactory.getPrice(0, amountArr[i], priceType, arg1, arg2)).to.equal(expectedPrice);
    }

    amountArr = [1, 2, 3, 4];
    expectedPriceArr = [5, 10, 15, 20];
    for (var i = 0; i < amountArr.length; i++) {
      let expectedPrice = ethers.utils.parseEther(expectedPriceArr[i].toString());
      expect(await memeFactory.getPrice(2, amountArr[i], priceType, arg1, arg2)).to.equal(expectedPrice);
    }
  });

  function buildMemeConf() {
    let conf = {};
    conf.maxSupply = toBn(100);
    conf.isNative = false;
    conf.isFT = false;
    conf.name = "name";
    conf.symbol = "symbol";
    conf.baseURI = "https://www.abc.com";
    conf.baseUnit = ethers.utils.parseEther("1");
    conf.priceType = toBn(1);
    conf.priceArg1 = ethers.utils.parseEther("1");
    conf.priceArg2 = ethers.utils.parseEther("1");
    return conf;
  }

  it("should be check meme conf", async function () {
    let conf = buildMemeConf();
    expect(await memeFactory.checkMemeConf(conf)).to.be.true;

    conf = buildMemeConf();
    conf.maxSupply = toBn(0);
    expect(await memeFactory.checkMemeConf(conf)).to.be.false;

    conf = buildMemeConf();
    conf.name = "";
    expect(await memeFactory.checkMemeConf(conf)).to.be.false;

    conf = buildMemeConf();
    conf.symbol = "";
    expect(await memeFactory.checkMemeConf(conf)).to.be.false;

    conf = buildMemeConf();
    conf.baseURI = "";
    expect(await memeFactory.checkMemeConf(conf)).to.be.false;

    conf = buildMemeConf();
    conf.baseUnit = ethers.utils.parseEther("0.9");
    expect(await memeFactory.checkMemeConf(conf)).to.be.false;

    conf = buildMemeConf();
    conf.priceType = toBn(0);
    expect(await memeFactory.checkMemeConf(conf)).to.be.false;
  });

  async function getSignature(hash, signer) {
    const privateKey = privateKeyByWallet[signer.address];
    return signPackedData(hash, privateKey);
  }

  it("should be new meme club", async function () {
    let conf = buildMemeConf();
    conf.isNative = true;

    let callId = 1;
    let hash = await memeFactory.hashForNewMemeClub(callId, conf);
    let signature = await getSignature(hash, validator);

    await expect(memeFactory.newMemeClub(callId, conf, signature))
      .to.emit(memeFactory, "MemeClubCreated")
      .withArgs(callId, anyValue, anyValue);

    await memeFactory.setLFGToken(lfg.address);
    callId = 2;
    hash = await memeFactory.hashForNewMemeClub(callId, conf);
    signature = await getSignature(hash, validator);
    await expect(memeFactory.newMemeClub(callId, conf, signature))
      .to.emit(memeFactory, "MemeClubCreated")
      .withArgs(callId, anyValue, anyValue);
  });

  it("should be new meme club(check property)", async function () {
    let conf = buildMemeConf();
    conf.isNative = true;

    let callId = 1;
    let clubId = chainId * 10000000 + 1;
    let hash = await memeFactory.hashForNewMemeClub(callId, conf);
    let signature = await getSignature(hash, validator);

    await expect(memeFactory.newMemeClub(callId, conf, signature))
      .to.emit(memeFactory, "MemeClubCreated")
      .withArgs(callId, clubId, anyValue);

    let club = await memeFactory.getMemeClub(clubId);

    expect(club.clubId).to.equal(clubId);
    expect(club.isLocked).to.be.false;
    expect(club.subjectAddress).to.equal(owner.address);
    expect(club.memeAddress).to.equal(addr0);
    expect(club.supply).to.equal(0);
    expect(club.funds).to.equal(0);

    expect(club.memeConf.maxSupply).to.equal(conf.maxSupply);
    expect(club.memeConf.isNative).to.equal(conf.isNative);
    expect(club.memeConf.isFT).to.equal(conf.isFT);
    expect(club.memeConf.name).to.equal(conf.name);
    expect(club.memeConf.symbol).to.equal(conf.symbol);
    expect(club.memeConf.baseURI).to.equal(conf.baseURI);
    expect(club.memeConf.baseUnit).to.equal(conf.baseUnit);
    expect(club.memeConf.priceType).to.equal(conf.priceType);
    expect(club.memeConf.priceArg1).to.equal(conf.priceArg1);
    expect(club.memeConf.priceArg2).to.equal(conf.priceArg2);
  });

  function randBetween(min, max) {
    let diff = max - min;
    return Math.floor(min + diff * Math.random());
  }

  it("should be pause", async function () {
    let conf = buildMemeConf();
    conf.isNative = true;

    let callId = 1;
    let hash = await memeFactory.hashForNewMemeClub(callId, conf);
    let signature = await getSignature(hash, validator);
    await expect(memeFactory.newMemeClub(callId, conf, signature)).to.emit(memeFactory, "MemeClubCreated");

    await memeFactory.pause();

    callId = 2;
    hash = await memeFactory.hashForNewMemeClub(callId, conf);
    signature = await getSignature(hash, validator);
    await expect(memeFactory.newMemeClub(callId, conf, signature)).to.be.revertedWith("Pausable: paused");

    await memeFactory.unpause();

    callId = 3;
    hash = await memeFactory.hashForNewMemeClub(callId, conf);
    signature = await getSignature(hash, validator);
    await expect(memeFactory.newMemeClub(callId, conf, signature)).to.emit(memeFactory, "MemeClubCreated");
  });
});
