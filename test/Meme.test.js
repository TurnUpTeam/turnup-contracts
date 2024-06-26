const {ethers, network} = require("hardhat");
const {ContractFactory, utils} = require("ethers");
const {expect} = require("chai");
const {anyValue} = require("@nomicfoundation/hardhat-chai-matchers/withArgs");
const DeployUtils = require("eth-deploy-utils");
const WETH9 = require("./WETH9.json");

const {signPackedData, privateKeyByWallet} = require("./helpers");

const artifacts = {
  UniswapV3Factory: require("@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol/UniswapV3Factory.json"),
  SwapRouter: require("@uniswap/v3-periphery/artifacts/contracts/SwapRouter.sol/SwapRouter.json"),
  NFTDescriptor: require("@uniswap/v3-periphery/artifacts/contracts/libraries/NFTDescriptor.sol/NFTDescriptor.json"),
  NonfungibleTokenPositionDescriptor: require("@uniswap/v3-periphery/artifacts/contracts/NonfungibleTokenPositionDescriptor.sol/NonfungibleTokenPositionDescriptor.json"),
  NonfungiblePositionManager: require("@uniswap/v3-periphery/artifacts/contracts/NonfungiblePositionManager.sol/NonfungiblePositionManager.json"),
  WETH9,
};

const linkLibraries = ({bytecode, linkReferences}, libraries) => {
  Object.keys(linkReferences).forEach((fileName) => {
    Object.keys(linkReferences[fileName]).forEach((contractName) => {
      if (!libraries.hasOwnProperty(contractName)) {
        throw new Error(`Missing link library name ${contractName}`);
      }
      const address = utils.getAddress(libraries[contractName]).toLowerCase().slice(2);
      linkReferences[fileName][contractName].forEach(({start, length}) => {
        const start2 = 2 + start * 2;
        const length2 = length * 2;
        bytecode = bytecode
          .slice(0, start2)
          .concat(address)
          .concat(bytecode.slice(start2 + length2, bytecode.length));
      });
    });
  });
  return bytecode;
};

describe("Meme", function () {
  let zeroEther, oneEther, millionEther, tooManyEther;
  let chainId;
  let owner, bob, alice, fred, tokenHolder, validator;

  let uniswapV3Factory;
  let uniswapPositionManager;
  let weth;

  let protocolFeeDestination;
  let lfg;
  let tokenFactory;
  let memeFactory;
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

    let contractFactory = new ContractFactory(artifacts.WETH9.abi, artifacts.WETH9.bytecode, owner);
    weth = await contractFactory.deploy();

    contractFactory = new ContractFactory(artifacts.UniswapV3Factory.abi, artifacts.UniswapV3Factory.bytecode, owner);
    uniswapV3Factory = await contractFactory.deploy();

    contractFactory = new ContractFactory(artifacts.SwapRouter.abi, artifacts.SwapRouter.bytecode, owner);
    swapRouter = await contractFactory.deploy(uniswapV3Factory.address, weth.address);

    contractFactory = new ContractFactory(artifacts.NFTDescriptor.abi, artifacts.NFTDescriptor.bytecode, owner);
    nftDescriptor = await contractFactory.deploy();

    const linkedBytecode = linkLibraries(
      {
        bytecode: artifacts.NonfungibleTokenPositionDescriptor.bytecode,
        linkReferences: {
          "NFTDescriptor.sol": {
            NFTDescriptor: [
              {
                length: 20,
                // start: 1261,
                start: 1681,
              },
            ],
          },
        },
      },
      {
        NFTDescriptor: nftDescriptor.address,
      }
    );

    contractFactory = new ContractFactory(artifacts.NonfungibleTokenPositionDescriptor.abi, linkedBytecode, owner);
    const nativeCurrencyLabelBytes = utils.formatBytes32String("WETH");
    nonfungibleTokenPositionDescriptor = await contractFactory.deploy(weth.address, nativeCurrencyLabelBytes);

    contractFactory = new ContractFactory(
      artifacts.NonfungiblePositionManager.abi,
      artifacts.NonfungiblePositionManager.bytecode,
      owner
    );
    uniswapPositionManager = await contractFactory.deploy(
      uniswapV3Factory.address,
      weth.address,
      nonfungibleTokenPositionDescriptor.address
    );

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

    memeFactory = await deployUtils.deployProxy(
      "MemeFactory",
      [validator.address],
      uniswapV3Factory.address,
      uniswapPositionManager.address,
      weth.address
    );

    tokenFactory = await deployUtils.deployProxy("TokenFactory", memeFactory.address);

    await memeFactory.setTokenFactory(tokenFactory.address);
    await memeFactory.setLFGToken(lfg.address);

    //console.log(await nonfungibleTokenPositionDescriptor.flipRatio())
  }

  beforeEach(async function () {
    await initAndDeploy();
  });

  it("should be initialized with the correct parameter", async function () {
    expect(await memeFactory.owner()).to.equal(owner.address);
    expect(await memeFactory.owner()).to.not.equal(bob.address);
    expect(await memeFactory.lfgToken()).to.equal(lfg.address);
    expect(await memeFactory.baseClubId()).to.equal(0);

    let feePercent = ethers.utils.parseEther("0.02");
    expect(await memeFactory.protocolFeePercent()).to.equal(feePercent);
 
    expect(await memeFactory.protocolLFGFees()).to.equal(0);
    expect(await memeFactory.protocolNativeFees()).to.equal(0);
  });

  it("should be update LFGToken", async function () {
    expect(await memeFactory.lfgToken()).to.equal(lfg.address);
    await expect(memeFactory.setLFGToken(lfg.address)).to.emit(memeFactory, "LfgTokenUpdate").withArgs(lfg.address);
    expect(await memeFactory.lfgToken()).to.equal(lfg.address);
    await expect(memeFactory.connect(bob).setLFGToken(lfg.address)).to.be.revertedWith("Ownable: caller is not the owner");
  });
 
  it("should be update protocol fee percent", async function () {
    let defaultPercent = ethers.utils.parseEther("0.02");
    expect(await memeFactory.protocolFeePercent()).to.equal(defaultPercent);
    let percent = ethers.utils.parseEther("0.53");
    await expect(memeFactory.setProtocolFeePercent(percent)).to.emit(memeFactory, "ProtocolFeePercentUpdate").withArgs(percent);
    expect(await memeFactory.protocolFeePercent()).to.equal(percent);

    await expect(memeFactory.connect(bob).setProtocolFeePercent(percent)).to.be.revertedWith(
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
    conf.liquidityAmount = ethers.utils.parseEther("10000");
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

  function now() {
    var timestamp = new Date().getTime()
    return Math.floor(timestamp / 1000)
  }

  it("should be new meme club", async function () {
    ////----
    /*
    let c = buildMemeConf()
    c.maxSupply = 10;
    c.isNative = true;
    c.isFT = false;
    c.name = "erer";
    c.symbol = "FWAEF";
    c.baseURI = "https://test.badass.xyz/memeclub_json";
    c.baseUnit = ethers.BigNumber.from("10000000000000000000000");
    c.priceType = ethers.BigNumber.from(1);
    c.priceArg1 = ethers.BigNumber.from("5000000000000000");
    c.priceArg2 = 0;
    let hash1 = await memeFactory.hashForNewMemeClub(80002, 64, "0xBC7fE00602139BF63527Fd7Ea608C1989708ec8E", c);
    console.log(hash1)
    */
    ////----

    let conf = buildMemeConf();
    conf.isNative = true;
    let t = now()

    let callId = 1;
    let hash = await memeFactory.hashForNewMemeClub(chainId, callId, owner.address, 0, conf, t, 120);
    let signature = await getSignature(hash, validator);

    await expect(memeFactory.newMemeClub(callId, 0, 0, conf, t, 120, signature))
      .to.emit(memeFactory, "MemeClubCreated")
      .withArgs(callId, anyValue, anyValue, anyValue);

    await memeFactory.setLFGToken(lfg.address);
    callId = 2;
    hash = await memeFactory.hashForNewMemeClub(chainId, callId, owner.address, 0, conf, t, 120);
    signature = await getSignature(hash, validator);
    await expect(memeFactory.newMemeClub(callId, 0, 0, conf, t, 120, signature))
      .to.emit(memeFactory, "MemeClubCreated")
      .withArgs(callId, anyValue, anyValue, anyValue);
  });

  it("should be new meme club(check property)", async function () {
    let conf = buildMemeConf();
    conf.isNative = true;
    let t = now()

    let callId = 1;
    let clubId = chainId * 10000000 + 1;
    let hash = await memeFactory.hashForNewMemeClub(chainId, callId, owner.address, 0, conf, t, 120);
    let signature = await getSignature(hash, validator);

    await expect(memeFactory.newMemeClub(callId, 0, 0, conf, t, 120, signature))
      .to.emit(memeFactory, "MemeClubCreated")
      .withArgs(callId, clubId, anyValue, anyValue);

    let club = await memeFactory.getMemeClub(clubId);

    expect(club.clubId).to.equal(clubId);
    expect(club.isLocked).to.be.false;
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

  it.skip("should be buyCard(LFG FT TGE)", async function () {
    await memeFactory.setLFGToken(lfg.address);
    await lfg.connect(tokenHolder).transfer(owner.address, millionEther);
    await lfg.connect(owner).approve(memeFactory.address, millionEther);

    let conf = buildMemeConf();
    conf.isFT = true;
    conf.isNative = false;
    conf.maxSupply = toBn(10);

    let callId = 1;
    let clubId = chainId * 10000000 + 1;
    let hash = await memeFactory.hashForNewMemeClub(chainId, callId, owner.address, conf);
    let signature = await getSignature(hash, validator);
    await expect(memeFactory.newMemeClub(1, 0, conf, signature))
      .to.emit(memeFactory, "MemeClubCreated")
      .withArgs(callId, clubId, anyValue);

    await expect(await memeFactory.buyCard(clubId, 9, millionEther)).to.emit(memeFactory, "MemeClubTrade");
    await expect(await memeFactory.buyCard(clubId, 1, millionEther)).to.emit(memeFactory, "MemeTokenGeneration");
  });

  it.skip("should be buyCard(LFG DN404 TGE)", async function () {
    await memeFactory.setLFGToken(lfg.address);
    await lfg.connect(tokenHolder).transfer(owner.address, millionEther);
    await lfg.connect(owner).approve(memeFactory.address, millionEther);

    let conf = buildMemeConf();
    conf.isFT = false;
    conf.isNative = false;
    conf.maxSupply = toBn(10);

    let callId = 1;
    let clubId = chainId * 10000000 + 1;
    let hash = await memeFactory.hashForNewMemeClub(chainId, callId, owner.address, conf);
    let signature = await getSignature(hash, validator);
    await expect(memeFactory.newMemeClub(1, 0, conf, signature))
      .to.emit(memeFactory, "MemeClubCreated")
      .withArgs(callId, clubId, anyValue);

    await expect(await memeFactory.buyCard(clubId, 9, millionEther)).to.emit(memeFactory, "MemeClubTrade");
    await expect(await memeFactory.buyCard(clubId, 1, millionEther)).to.emit(memeFactory, "MemeTokenGeneration");
  });

  function randBetween(min, max) {
    let diff = max - min;
    return Math.floor(min + diff * Math.random());
  }

  it("should be pause", async function () {
    let conf = buildMemeConf();
    conf.isNative = true;
    let t = now()
    
    let callId = 1;
    let hash = await memeFactory.hashForNewMemeClub(chainId, callId, owner.address, 0, conf, t, 120);
    let signature = await getSignature(hash, validator);
    await expect(memeFactory.newMemeClub(callId, 0, 0, conf, t, 120, signature)).to.emit(memeFactory, "MemeClubCreated");

    await memeFactory.pause();

    callId = 2;
    hash = await memeFactory.hashForNewMemeClub(chainId, callId, owner.address, 0, conf, t, 120);
    signature = await getSignature(hash, validator);
    await expect(memeFactory.newMemeClub(callId, 0, 0, conf, t, 120, signature)).to.be.revertedWith("Pausable: paused");

    await memeFactory.unpause();

    callId = 3;
    hash = await memeFactory.hashForNewMemeClub(chainId, callId, owner.address, 0, conf, t, 120);
    signature = await getSignature(hash, validator);
    await expect(memeFactory.newMemeClub(callId, 0, 0, conf, t, 120, signature)).to.emit(memeFactory, "MemeClubCreated");
  });
});
