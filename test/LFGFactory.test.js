const {expect} = require("chai");
const EthDeployUtils = require("eth-deploy-utils");

const deployUtils = new EthDeployUtils();

const {signPackedData, privateKeyByWallet, getTimestamp, addr0, increaseBlockTimestampBy} = require("./helpers");
const {ethers} = require("hardhat");

describe("LFGFactory", function () {
  let factory;
  let lfg;

  let owner, bob, alice, fred, operator, validator, tokenHolder;

  const BurnReason = {
    UnlockMission: 0,
    LootFee: 1,
  };

  before(async function () {
    [owner, bob, alice, fred, operator, validator, tokenHolder] = await ethers.getSigners();
  });

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
      amountReservedToSharesPool,
      maxLockTime
    );

    const maxDaily = (await lfg.amountReservedToPool()).div(365);

    factory = await deployUtils.deployProxy("LFGFactory", lfg.address, [validator.address], maxDaily);

    await factory.setOperator(operator.address, true);

    await lfg.setFactory(factory.address);
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

      let hash = await factory.hashLfgApply(orderId, amount, lockedUntil, bob.address, ts, validFor);
      let signature = await getSignature(hash, validator);

      await expect(factory.connect(bob).applyToMintLfg(orderId, amount, lockedUntil, ts, validFor, signature))
        .to.emit(factory, "MintRequested")
        .withArgs(orderId, amount, bob.address, lockedUntil);

      expect(await lfg.countLocksOf(bob.address)).to.equal(1);
      const locks = await lfg.locksOf(bob.address);
      expect(locks.length).to.equal(1);
      expect(locks[0].amount).to.equal(amount);
      expect(locks[0].lockedUntil).to.equal(lockedUntil);

      expect(await lfg.balanceOf(bob.address)).to.equal(amount);
      expect(await lfg.availableBalanceOf(bob.address)).to.equal(0);

      await expect(lfg.connect(bob).transfer(alice.address, amount.div(10))).revertedWith("InsufficientAllowance");

      await increaseBlockTimestampBy(lockedUntil - ts + 1);

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

      let hash = await factory.hashLfgApply(orderId, amount, lockedUntil, bob.address, ts, validFor);
      let signature = await getSignature(hash, validator);

      await expect(factory.connect(bob).applyToMintLfg(orderId, amount, lockedUntil, ts, validFor, signature))
        .to.emit(factory, "MintRequested")
        .withArgs(orderId, amount, bob.address, lockedUntil);

      expect(await lfg.balanceOf(bob.address)).to.equal(amount);
      expect(await lfg.availableBalanceOf(bob.address)).to.equal(0);

      await expect(factory.connect(owner).cancelApplicationToMintLfg(orderId)).revertedWith("NotAuthorized");

      await expect(factory.connect(operator).cancelApplicationToMintLfg(orderId))
        .emit(factory, "CancelRequest")
        .withArgs(orderId, amount, bob.address, lockedUntil);

      await increaseBlockTimestampBy(lockedUntil - ts + 1);

      await expect(lfg.connect(bob).transfer(alice.address, amount.div(10))).revertedWith(
        "ERC20: transfer amount exceeds balance"
      );
    });
  });

  describe("burnLfg", function () {
    it("should burn LFG correctly", async function () {
      let amount = ethers.utils.parseEther("100");
      let orderId = 1;
      let ts = await getTimestamp();
      let lockedUntil = ts + 60 * 60 * 24; // 24 hours from now
      let validFor = 60 * 60 * 2;

      let hash = await factory.hashLfgApply(orderId, amount, lockedUntil, bob.address, ts, validFor);
      let signature = await getSignature(hash, validator);

      await expect(factory.connect(bob).applyToMintLfg(orderId, amount, lockedUntil, ts, validFor, signature))
        .to.emit(factory, "MintRequested")
        .withArgs(orderId, amount, bob.address, lockedUntil);

      await increaseBlockTimestampBy(lockedUntil - ts + 1);

      const balance = await lfg.balanceOf(bob.address);
      expect(balance).to.equal(amount);

      const reason = BurnReason.UnlockMission; // or BurnReason.LootFee depending on the scenario
      orderId = 2;
      const burnedAmount = ethers.utils.parseEther("10");
      ts = await getTimestamp();
      validFor = 3600;
      hash = await factory.hashBurnLfg(orderId, bob.address, reason, burnedAmount, ts, validFor);
      signature = await getSignature(hash, validator);

      await expect(factory.connect(bob).burnLfg(orderId, burnedAmount, reason, ts, validFor, signature))
        .to.emit(lfg, "Transfer")
        .withArgs(bob.address, addr0, burnedAmount);

      const balanceAfterBurn = await lfg.balanceOf(bob.address);
      expect(balanceAfterBurn).to.equal(balance.sub(burnedAmount));
    });
  });
});
