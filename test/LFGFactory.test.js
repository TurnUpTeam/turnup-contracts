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

describe("LFGFactory", function () {
  let factory;
  let lfg;
  let pool;

  let owner, bob, alice, fred, operator, validator, tokenHolder;

  let MintType = {
    Mint: 0,
    MintAndStake: 1,
    MintAndBurn: 2,
  };

  const blocksPerDay = 42000;
  const blocksPerWeek = blocksPerDay * 7;
  const twoYearsBlocks = blocksPerDay * 365 * 2;
  const reservedToTool = 400000000;
  const amountReservedToPool = ethers.utils.parseEther(reservedToTool.toString());
  const minLockTime = 3600 * 24 * 7 * 16;

  const BurnReason = {
    UnlockMission: 0,
    LootFee: 1,
  };

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

  describe("applyToMintLfg", function () {
    it("should apply LFG correctly", async function () {
      const orderId = 1;
      const amount = ethers.utils.parseEther("1");
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
    });

    it("should cancel to stake LFG correctly", async function () {
      const orderId = 1;
      const amount = ethers.utils.parseEther("1");
      const ts = await getTimestamp();
      let lockedUntil = ts + 60 * 60 * 24; // 24 hours from now
      let validFor = 60 * 60 * 2;
      const t90days = 3600 * 24 * 90;
      // staking until 90 days from now
      const stakeLockedUntil = ts + t90days;

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

      await expect(factory.connect(owner).cancelApplicationToMintLfgAndStake(orderId, bob.address)).revertedWith(
        "NotAuthorized"
      );

      await expect(factory.connect(operator).cancelApplicationToMintLfgAndStake(orderId, bob.address))
        .emit(factory, "CancelStakeRequest")
        .withArgs(orderId, amount, bob.address, lockedUntil, stakeLockedUntil);

      expect(await lfg.balanceOf(bob.address)).to.equal(0);
    });

    it("should return true for signature already used", async function () {
      const orderId = 1;
      const amount = ethers.utils.parseEther("1");
      const ts = await getTimestamp();
      const lockedUntil = ts + 60 * 60 * 24; // 24 hours from now
      const validFor = 60 * 60 * 2;

      let hash = await factory.hashForApplyToMintLfg(orderId, amount, lockedUntil, false, bob.address, ts, validFor);
      let signature = await getSignature(hash, validator);

      await factory.connect(bob).applyToMintLfg(orderId, amount, lockedUntil, ts, validFor, signature);

      expect(await factory.connect(bob).isSignatureUsed(signature)).to.equal(true);
    });

    it("testing operator function", async function () {
      expect(await factory.connect(operator).isOperator(operator.address)).to.equal(true);

      await expect(factory.setOperator(operator.address, true)).revertedWith("OperatorAlreadySet()");

      await expect(factory.setOperator(operator.address, false)).emit(factory, "OperatorSet").withArgs(operator.address, false);

      expect(await factory.connect(operator).isOperator(operator.address)).to.equal(false);

      await expect(factory.setOperator(operator.address, false)).revertedWith("OperatorNotSet()");

      await expect(factory.setOperator(operator.address, true)).emit(factory, "OperatorSet").withArgs(operator.address, true);

      expect(await factory.connect(operator).isOperator(operator.address)).to.equal(true);
    });

    it("testing setting min lock time", async function () {
      await factory.connect(owner).setMinLockTime(43500);
      expect(await factory.minLockTime()).to.equal("43500");
    });

    it("testing get daily minted", async function () {
      let orderId = 1;
      let amount = ethers.utils.parseEther("1");
      let ts = await getTimestamp();
      let lockedUntil = ts + 60 * 60 * 24; // 24 hours from now
      let validFor = 60 * 60 * 2;

      let hash = await factory.hashForApplyToMintLfg(orderId, amount, lockedUntil, false, bob.address, ts, validFor);
      let signature = await getSignature(hash, validator);

      await expect(factory.connect(bob).applyToMintLfg(orderId, amount, lockedUntil, ts, validFor, signature))
        .to.emit(factory, "MintRequested")
        .withArgs(orderId, amount, bob.address, lockedUntil);

      await increaseBlocksBy(lockedUntil - ts + 1);

      await factory.connect(bob).claimAllPending();

      let today = (await getTimestamp()) / 86400;
      today = Math.floor(today);

      expect(await factory.getDailyMinted(today)).to.equal(ethers.utils.parseEther("1"));
    });

    it("should apply to mint LFG two times, collecting pending", async function () {
      let orderId = 1;
      let amount = ethers.utils.parseEther("1");
      let ts = await getTimestamp();
      let lockedUntil = ts + 60 * 60 * 24; // 24 hours from now
      let validFor = 60 * 60 * 2;

      let hash = await factory.hashForApplyToMintLfg(orderId, amount, lockedUntil, false, bob.address, ts, validFor);
      let signature = await getSignature(hash, validator);

      await expect(factory.connect(bob).applyToMintLfg(orderId, amount, lockedUntil, ts, validFor, signature))
        .to.emit(factory, "MintRequested")
        .withArgs(orderId, amount, bob.address, lockedUntil);

      const request = await factory.getMintRequest(bob.address);
      expect(request.amount).to.equal(amount);
      expect(request.lockedUntil).to.equal(lockedUntil);
      expect(request.orderId).to.equal(orderId);

      expect(await lfg.balanceOf(bob.address)).to.equal(0);

      await increaseBlockTimestampBy(lockedUntil - ts + 1);

      orderId++;
      ts = await getTimestamp();
      lockedUntil += 60 * 60 * 24; // 24 hours from now

      hash = await factory.hashForApplyToMintLfg(orderId, amount, lockedUntil, false, bob.address, ts, validFor);
      signature = await getSignature(hash, validator);

      await expect(factory.connect(bob).applyToMintLfg(orderId, amount, lockedUntil, ts, validFor, signature))
        .to.emit(factory, "MintRequested")
        .withArgs(orderId, amount, bob.address, lockedUntil)
        .to.emit(lfg, "Transfer")
        .withArgs(factory.address, bob.address, amount);

      await expect(lfg.connect(bob).transfer(alice.address, amount.div(10)))
        .to.emit(lfg, "Transfer")
        .withArgs(bob.address, alice.address, amount.div(10));
    });

    it("operator should cancel orderId", async function () {
      const orderId = 1;
      const amount = ethers.utils.parseEther("1");
      const ts = await getTimestamp();
      const lockedUntil = ts + 60 * 60 * 24; // 24 hours from now
      const validFor = 60 * 60 * 2;

      let hash = await factory.hashForApplyToMintLfg(orderId, amount, lockedUntil, false, bob.address, ts, validFor);
      let signature = await getSignature(hash, validator);

      await expect(factory.connect(bob).applyToMintLfg(orderId, amount, lockedUntil, ts, validFor, signature))
        .to.emit(factory, "MintRequested")
        .withArgs(orderId, amount, bob.address, lockedUntil);

      expect(await lfg.balanceOf(bob.address)).to.equal(0);

      await expect(factory.connect(owner).cancelApplicationToMintLfg(orderId, bob.address)).revertedWith("NotAuthorized");

      await expect(factory.connect(operator).cancelApplicationToMintLfg(orderId, bob.address))
        .emit(factory, "CancelRequest")
        .withArgs(orderId, amount, bob.address, lockedUntil);

      await increaseBlockTimestampBy(lockedUntil - ts + 1);

      expect(await lfg.balanceOf(bob.address)).to.equal(0);
    });
  });

  describe("burnLfg", function () {
    it("should burn LFG correctly", async function () {
      let amount = ethers.utils.parseEther("100");
      let orderId = 1;
      let ts = await getTimestamp();
      let lockedUntil = ts + 60 * 60 * 24; // 24 hours from now
      let validFor = 60 * 60 * 2;

      let hash = await factory.hashForApplyToMintLfg(orderId, amount, lockedUntil, false, bob.address, ts, validFor);
      let signature = await getSignature(hash, validator);

      await expect(factory.connect(bob).applyToMintLfg(orderId, amount, lockedUntil, ts, validFor, signature))
        .to.emit(factory, "MintRequested")
        .withArgs(orderId, amount, bob.address, lockedUntil);

      await increaseBlockTimestampBy(lockedUntil - ts + 1);

      await factory.connect(bob).claimAllPending();

      const balance = await lfg.balanceOf(bob.address);
      expect(balance).to.equal(amount);

      const reason = BurnReason.UnlockMission; // or BurnReason.LootFee depending on the scenario
      orderId = 2;
      const burnedAmount = ethers.utils.parseEther("10");
      ts = await getTimestamp();
      validFor = 3600;
      hash = await factory.hashBurnLfg(orderId, bob.address, reason, burnedAmount, false, ts, validFor);
      signature = await getSignature(hash, validator);

      await expect(factory.connect(bob).burnLfg(orderId, burnedAmount, false, reason, ts, validFor, signature))
        .to.emit(lfg, "Transfer")
        .withArgs(bob.address, addr0, burnedAmount);

      const balanceAfterBurn = await lfg.balanceOf(bob.address);
      expect(balanceAfterBurn).to.equal(balance.sub(burnedAmount));
    });

    it("should burn LFG correctly different burn reason", async function () {
      let amount = ethers.utils.parseEther("100");
      let orderId = 1;
      let ts = await getTimestamp();
      let lockedUntil = ts + 60 * 60 * 24; // 24 hours from now
      let validFor = 60 * 60 * 2;

      let hash = await factory.hashForApplyToMintLfg(orderId, amount, lockedUntil, false, bob.address, ts, validFor);
      let signature = await getSignature(hash, validator);

      await expect(factory.connect(bob).applyToMintLfg(orderId, amount, lockedUntil, ts, validFor, signature))
        .to.emit(factory, "MintRequested")
        .withArgs(orderId, amount, bob.address, lockedUntil);

      await increaseBlockTimestampBy(lockedUntil - ts + 1);

      await factory.connect(bob).claimAllPending();

      const balance = await lfg.balanceOf(bob.address);
      expect(balance).to.equal(amount);

      const reason = BurnReason.LootFee; // or BurnReason.UnlockMission depending on the scenario
      orderId = 2;
      const burnedAmount = ethers.utils.parseEther("10");
      ts = await getTimestamp();
      validFor = 3600;
      hash = await factory.hashBurnLfg(orderId, bob.address, reason, burnedAmount, false, ts, validFor);
      signature = await getSignature(hash, validator);

      await expect(factory.connect(bob).burnLfg(orderId, burnedAmount, false, reason, ts, validFor, signature))
        .to.emit(lfg, "Transfer")
        .withArgs(bob.address, addr0, burnedAmount);

      const balanceAfterBurn = await lfg.balanceOf(bob.address);
      expect(balanceAfterBurn).to.equal(balance.sub(burnedAmount));
    });

    it("should mint and burn LFG correctly", async function () {
      let amount = ethers.utils.parseEther("100");
      let orderId = 1;
      let ts = await getTimestamp();
      let lockedUntil = ts + 60 * 60 * 24; // 24 hours from now
      let validFor = 60 * 60 * 2;

      const reason = BurnReason.UnlockMission; // or BurnReason.LootFee depending on the scenario
      orderId = 2;
      const burnedAmount = ethers.utils.parseEther("10");
      ts = await getTimestamp();
      validFor = 3600;
      let hash = await factory.hashBurnLfg(orderId, bob.address, reason, burnedAmount, true, ts, validFor);
      let signature = await getSignature(hash, validator);

      const balance = await lfg.balanceOf(bob.address);
      expect(balance).to.equal(0);

      await expect(factory.connect(bob).burnLfg(orderId, burnedAmount, true, reason, ts, validFor, signature))
        .to.emit(lfg, "Transfer")
        .withArgs(factory.address, addr0, burnedAmount);

      const balanceAfterBurn = await lfg.balanceOf(bob.address);
      expect(balanceAfterBurn).to.equal(0);
    });
  });

  describe("applyToMintLfgAndStake", function () {
    it("should apply to stake LFG correctly", async function () {
      const orderId = 1;
      const amount = ethers.utils.parseEther("1");
      const ts = await getTimestamp();
      let lockedUntil = ts + 60 * 60 * 24; // 24 hours from now
      let validFor = 60 * 60 * 2;
      const t90days = 3600 * 24 * 90;
      // staking until 90 days from now
      const stakeLockedUntil = ts + t90days;

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

      await increaseBlockTimestampBy(stakeLockedUntil - ts + t90days + 1);

      let bobBalanceBefore = await lfg.balanceOf(bob.address);
      let pendingYieldingRewards = await pool.pendingYieldRewards(bob.address);
      expect(pendingYieldingRewards).to.be.equal("31578947368421048785");

      await expect(pool.connect(bob).unstake(0, amount)).to.emit(pool, "Unstaked").withArgs(bob.address, amount);
    });

    it("should apply to stake LFG and claim late", async function () {
      const orderId = 1;
      const amount = ethers.utils.parseEther("1");
      const ts = await getTimestamp();
      const t90days = 3600 * 24 * 90;
      let lockedUntil = ts + 60 * 60 * 24; // 24 hours from now
      let validFor = 60 * 60 * 2;
      // staking until 90 days from now
      const stakeLockedUntil = ts + 3600 * 24 * 30; // the minimum

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
      await increaseBlockTimestampBy(lockedUntil - ts + 3600 * 100);

      await expect(factory.connect(bob).claimAllPending())
        .to.emit(lfg, "Transfer")
        .withArgs(addr0, pool.address, amount)
        .to.emit(pool, "Staked")
        .withArgs(bob.address, amount)
        .to.emit(factory, "UpdateStakeLockedUntil");

      await increaseBlockTimestampBy(stakeLockedUntil - ts + t90days + 1);

      let bobBalanceBefore = await lfg.balanceOf(bob.address);
      let pendingYieldingRewards = await pool.pendingYieldRewards(bob.address);
      expect(pendingYieldingRewards).to.be.equal("31578947368421048785");

      await expect(pool.connect(bob).unstake(0, amount)).to.emit(pool, "Unstaked").withArgs(bob.address, amount);
    });
  });
});
