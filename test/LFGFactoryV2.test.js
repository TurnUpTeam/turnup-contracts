const {expect} = require("chai");
const EthDeployUtils = require("eth-deploy-utils");

const deployUtils = new EthDeployUtils();

const {
  signPackedData,
  privateKeyByWallet,
  getTimestamp,
  addr0,
  increaseBlockTimestampBy,
  getBlockNumber,
  cl,
} = require("./helpers");
const {ethers} = require("hardhat");

describe("LFGFactoryV2", function () {
  let factory;
  let lfg;
  let lfg2;
  let pool;

  let owner, bob, alice, fred, operator, validator, tokenHolder;

  const blocksPerDay = 42000;
  const reservedToTool = 400000000;
  const amountReservedToPool = ethers.utils.parseEther(reservedToTool.toString());
  const minLockTime = 3600 * 24 * 7 * 16;

  before(async function () {
    [owner, bob, alice, fred, operator, validator, tokenHolder] = await ethers.getSigners();
  });

  async function increaseBlocksBy(seconds) {
    let blockNumber = (await pool.blockNumber()).toNumber();
    // console.log("increasing blocks by", seconds, "seconds, and", Math.floor(blocksPerDay * (seconds / 86400)), "blocks.");
    await increaseBlockTimestampBy(seconds);
    let newBlockNumber = blockNumber + Math.floor((blocksPerDay * seconds) / 86400);
    await pool.setFakeBlockNumber(newBlockNumber);
    return newBlockNumber;
  }

  async function initAndDeploy() {
    let maxSupply = ethers.utils.parseEther("3000000000");
    let initialSupply = ethers.utils.parseEther("900000000");
    let initialSupplyLFGV2 = initialSupply.div(5);
    let amountReservedToPool = ethers.utils.parseEther("300000000");
    let amountReservedToSharesPool = ethers.utils.parseEther("200000000");
    let maxLockTime = 365 * 24 * 3600;
    lfg = await deployUtils.deployProxy(
      "LFGToken",
      tokenHolder.address,
      maxSupply,
      initialSupply,
      amountReservedToPool,
      amountReservedToSharesPool
    );

    lfg2 = await deployUtils.deploy("LFGTokenV2", "LFGTokenV2", "LFG2", initialSupplyLFGV2, tokenHolder.address);

    const maxDaily = (await lfg.amountReservedToPool()).div(365);

    factory = await deployUtils.deployProxy(
      "LFGFactory",
      lfg.address,
      [validator.address],
      maxDaily,
      // 12 hours
      3600 * 12
    );

    await factory.setOperator(operator.address, true);

    await lfg.setFactory(factory.address);
    await lfg2.setFactory(factory.address);

    const blockNumber = await getBlockNumber();

    pool = await deployUtils.deployProxy(
      "CorePoolMock",
      lfg.address,
      blockNumber + 2,
      minLockTime,
      amountReservedToPool,
      factory.address
    );

    await lfg.setPool(pool.address);
    await factory.setPool(pool.address);
    await factory.setLFGTokenV2(lfg2.address);
  }

  async function getSignature(hash, signer) {
    const privateKey = privateKeyByWallet[signer.address];
    return signPackedData(hash, privateKey);
  }

  beforeEach(async function () {
    await initAndDeploy();
  });

  it("should deploy and init", async function () {
    // check the initAndDeploy function
  });

  describe("applyToMintLfg2", function () {
    it("should return the token uri of the contract", async function () {
      await lfg2.setBaseURI("Uri/");
      expect(await lfg2.tokenURI(1)).equal("Uri/1");
    });

    it("should return the total supply", async function () {
      expect(await lfg2.totalSupply()).equal("180000000000000000000000000");
    });

    it("should return the name of the contract", async function () {
      expect(await lfg2.name()).equal("LFGTokenV2");
    });

    it("should return the symbol", async function () {
      expect(await lfg2.symbol()).equal("LFG2");
    });

    it("should apply LFG correctly and swap for LFG2", async function () {
      const orderId = 1;
      const amount = ethers.utils.parseEther("1");
      const amountToSwap = ethers.utils.parseEther("0.5");
      const ts = await getTimestamp();
      const lockedUntil = ts + 60 * 60 * 24; // 24 hours from now
      const validFor = 60 * 60 * 2;

      let hash = await factory.hashForApplyToMintLfg(orderId, amount, ts + 3600, false, bob.address, ts, validFor);
      let signature = await getSignature(hash, validator);

      await expect(factory.connect(bob).applyToMintLfg(orderId, amount, ts + 3600, ts, validFor, signature)).revertedWith(
        "InvalidLockTime()"
      );

      hash = await factory.hashForApplyToMintLfg(orderId, amount, lockedUntil, false, bob.address, ts, validFor);
      signature = await getSignature(hash, validator);

      await expect(factory.connect(bob).applyToMintLfg(orderId, amount, lockedUntil, ts, validFor, signature))
        .to.emit(factory, "MintRequested")
        .withArgs(orderId, amount, bob.address, lockedUntil);

      const request = await factory.getMintRequest(bob.address);
      expect(request.amount).to.equal(amount);
      expect(request.lockedUntil).to.equal(lockedUntil);
      expect(request.orderId).to.equal(orderId);

      expect(await lfg.balanceOf(bob.address)).to.equal(0);

      await increaseBlockTimestampBy(lockedUntil - ts + 1);

      await expect(factory.connect(bob).claimAllPending())
        .to.emit(lfg, "Transfer")
        .withArgs(factory.address, bob.address, amount);

      await expect(lfg.connect(bob).transfer(alice.address, amount.div(10)))
        .to.emit(lfg, "Transfer")
        .withArgs(bob.address, alice.address, amount.div(10));

      await factory.connect(bob).swapLfgFromV1ToV2(amountToSwap);
      expect(await lfg2.balanceOf(bob.address)).equal(amountToSwap);
    });

    it("should rewards From Lfg Staked In CorePool", async function () {
      const orderId = 1;
      const amount = ethers.utils.parseEther("1");
      const ts = await getTimestamp();
      let lockedUntil = ts + 60 * 60 * 24;
      let validFor = 60 * 60 * 2;
      const t90days = 3600 * 24 * 90;
      const stakeLockedUntil = ts + t90days;
      let daysInSeconds = 365 * 86400;

      let hash = await factory.hashForApplyToMintLfgAndStake(
        orderId,
        amount,
        lockedUntil,
        stakeLockedUntil,
        bob.address,
        ts,
        validFor
      );
      let signature = await getSignature(hash, validator);

      await expect(
        factory.connect(bob).applyToMintLfgAndStake(orderId, amount, lockedUntil, stakeLockedUntil, ts, validFor, signature)
      )
        .to.emit(factory, "MintAndStakeRequested")
        .withArgs(orderId, amount, bob.address, lockedUntil, stakeLockedUntil);
      await increaseBlockTimestampBy(lockedUntil - ts + 1);

      await expect(factory.connect(bob).claimAllPending())
        .to.emit(lfg, "Transfer")
        .withArgs(addr0, pool.address, amount)
        .to.emit(pool, "Staked");

      const deposit = await pool.getDeposit(bob.address, 0);
      const weight = 1 + Math.floor((deposit.lockedUntil - deposit.lockedFrom) / daysInSeconds);
      let value = deposit.tokenAmount.mul(weight).mul(10).div(100);

      await factory.connect(bob).rewardsFromLfgStakedInCorePool(0);
      expect(await lfg2.balanceOf(bob.address)).equal(value.toString());
    });
  });
  describe("should reverter LFGV2", function () {
    it("should revert when setting again", async function () {
      await expect(factory.setLFGTokenV2(lfg2.address)).to.revertedWith("AlreadySet()");
    });

    it("should revert when swapping insufficient balance", async function () {
      const orderId = 1;
      const amount = ethers.utils.parseEther("1");
      const amountToSwap = ethers.utils.parseEther("0.5");
      const ts = await getTimestamp();
      const lockedUntil = ts + 60 * 60 * 24; // 24 hours from now
      const validFor = 60 * 60 * 2;

      let hash = await factory.hashForApplyToMintLfg(orderId, amount, ts + 3600, false, bob.address, ts, validFor);
      let signature = await getSignature(hash, validator);

      await expect(factory.connect(bob).applyToMintLfg(orderId, amount, ts + 3600, ts, validFor, signature)).revertedWith(
        "InvalidLockTime()"
      );

      hash = await factory.hashForApplyToMintLfg(orderId, amount, lockedUntil, false, bob.address, ts, validFor);
      signature = await getSignature(hash, validator);

      await expect(factory.connect(bob).applyToMintLfg(orderId, amount, lockedUntil, ts, validFor, signature))
        .to.emit(factory, "MintRequested")
        .withArgs(orderId, amount, bob.address, lockedUntil);

      const request = await factory.getMintRequest(bob.address);
      expect(request.amount).to.equal(amount);
      expect(request.lockedUntil).to.equal(lockedUntil);
      expect(request.orderId).to.equal(orderId);

      expect(await lfg.balanceOf(bob.address)).to.equal(0);

      await increaseBlockTimestampBy(lockedUntil - ts + 1);

      await expect(factory.connect(bob).claimAllPending())
        .to.emit(lfg, "Transfer")
        .withArgs(factory.address, bob.address, amount);

      await expect(lfg.connect(bob).transfer(alice.address, amount.div(10)))
        .to.emit(lfg, "Transfer")
        .withArgs(bob.address, alice.address, amount.div(10));

      try {
        await factory.connect(alice).swapLfgFromV1ToV2(amountToSwap);
      } catch (e) {
        expect(e.message).to.include("ERC20: burn amount exceeds balance");
      }
    });

    it("should revert when passing wrong deposit ID", async function () {
      const orderId = 1;
      const amount = ethers.utils.parseEther("1");
      const ts = await getTimestamp();
      let lockedUntil = ts + 60 * 60 * 24;
      let validFor = 60 * 60 * 2;
      const t90days = 3600 * 24 * 90;
      const stakeLockedUntil = ts + t90days;
      let daysInSeconds = 365 * 86400;

      let hash = await factory.hashForApplyToMintLfgAndStake(
        orderId,
        amount,
        lockedUntil,
        stakeLockedUntil,
        bob.address,
        ts,
        validFor
      );
      let signature = await getSignature(hash, validator);

      await expect(
        factory.connect(bob).applyToMintLfgAndStake(orderId, amount, lockedUntil, stakeLockedUntil, ts, validFor, signature)
      )
        .to.emit(factory, "MintAndStakeRequested")
        .withArgs(orderId, amount, bob.address, lockedUntil, stakeLockedUntil);

      await increaseBlockTimestampBy(lockedUntil - ts + 1);

      await expect(factory.connect(bob).claimAllPending())
        .to.emit(lfg, "Transfer")
        .withArgs(addr0, pool.address, amount)
        .to.emit(pool, "Staked");

      const deposit = await pool.getDeposit(bob.address, 0);
      const weight = 1 + Math.floor((deposit.lockedUntil - deposit.lockedFrom) / daysInSeconds);
      let value = deposit.tokenAmount.mul(weight).mul(10).div(100);

      try {
        await factory.connect(bob).rewardsFromLfgStakedInCorePool(1);
      } catch (e) {
        expect(e.message).to.include("reverted with panic code 0x32");
      }
    });
  });
});
