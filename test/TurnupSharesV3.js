const {ethers, upgrades} = require("hardhat");
const {expect} = require("chai");
const DeployUtils = require("../scripts/lib/DeployUtils");

describe("TurnupSharesV3", function () {
  let turnupShares;
  let owner;
  let project;
  let buyer, buyer2, buyer3, wished;
  let subject;

  const deployUtils = new DeployUtils(ethers);

  before(async function () {
    [owner, project, buyer, buyer2, buyer3, wished] = await ethers.getSigners();
    subject = owner.address;
  });

  beforeEach(async function () {
    turnupShares = await deployUtils.deployProxy("TurnupSharesV3");
    expect(await turnupShares.getVer()).to.equal("v3.0.0");
  });

  async function init() {
    await turnupShares.setFeeDestination(project.address);
    const protocolFee = ethers.utils.parseUnits("50000000", "gwei"); // example fee
    await turnupShares.setProtocolFeePercent(protocolFee);
    const subjectFee = ethers.utils.parseUnits("50000000", "gwei"); // example fee
    await turnupShares.setSubjectFeePercent(subjectFee);
  }

  async function executeAndReturnGasCost(call) {
    const tx = await call;
    const receipt = await tx.wait(); // Wait for transaction to be mined to get the receipt
    const gasUsed = receipt.gasUsed;
    const txDetails = await ethers.provider.getTransaction(receipt.transactionHash);
    return gasUsed.mul(txDetails.gasPrice);
  }

  it("should be initialized with the correct owner", async function () {
    expect(await turnupShares.owner()).to.equal(owner.address);
  });

  it("should allow the owner to set fee destination", async function () {
    await turnupShares.setFeeDestination(project.address);
    expect(await turnupShares.protocolFeeDestination()).to.equal(project.address);
  });

  it("should allow the owner to set protocol fee percent", async function () {
    const protocolFee = ethers.utils.parseUnits("5", "wei"); // example fee
    await turnupShares.setProtocolFeePercent(protocolFee);
    expect(await turnupShares.protocolFeePercent()).to.equal(protocolFee);
  });

  it("should allow the owner to set subject fee percent", async function () {
    const subjectFee = ethers.utils.parseUnits("5", "wei"); // example fee
    await turnupShares.setSubjectFeePercent(subjectFee);
    expect(await turnupShares.subjectFeePercent()).to.equal(subjectFee);
  });

  it("should show that the price is consistent", async function () {
    await init();

    // owner buys shares

    const amount = ethers.BigNumber.from("10");

    let expectedPrice = await turnupShares.getBuyPriceAfterFee(subject, 1);
    await turnupShares.buyShares(subject, 1, {value: expectedPrice});

    expectedPrice = await turnupShares.getBuyPriceAfterFee(subject, 2 * amount);
    await turnupShares.connect(buyer2).buyShares(subject, 2 * amount, {value: expectedPrice});

    expectedPrice = await turnupShares.getBuyPriceAfterFee(subject, amount);
    await turnupShares.connect(buyer).buyShares(subject, 1, {value: expectedPrice});
    expect(await turnupShares.sharesSupply(subject)).to.equal(22);

    const buyerBalance = await ethers.provider.getBalance(buyer.address);
    expectedPrice = await turnupShares.getBuyPriceAfterFee(subject, amount);
    await turnupShares.connect(buyer).buyShares(subject, amount, {value: expectedPrice});
    await turnupShares.connect(buyer).sellShares(subject, amount);

    expect(buyerBalance.gt(await ethers.provider.getBalance(buyer.address))).equal(true);
  });

  it("should allow users to buy its own share", async function () {
    await init();
    // Assuming the initial supply is 0, owner is buying the first shares, and the price calculation function works correctly.
    const amount = 3; // example amount

    // notice that subject == owner.address
    let buyPrice = await turnupShares.getBuyPrice(subject, amount);
    let protocolFee = await turnupShares.getProtocolFee(buyPrice);
    let subjectFee = await turnupShares.getSubjectFee(buyPrice);
    let expectedPrice = await turnupShares.getBuyPriceAfterFee(subject, amount);
    expect(expectedPrice).to.equal(buyPrice.add(protocolFee).add(subjectFee));

    let projectBalance = await ethers.provider.getBalance(project.address);
    let ownerBalance = await ethers.provider.getBalance(subject);
    let contractBalance = await ethers.provider.getBalance(turnupShares.address);

    let gasCost = await executeAndReturnGasCost(turnupShares.buyShares(subject, amount, {value: expectedPrice}));

    expect(await ethers.provider.getBalance(project.address)).equal(projectBalance.add(protocolFee));
    expect(await ethers.provider.getBalance(subject)).equal(ownerBalance.sub(expectedPrice).sub(gasCost).add(subjectFee));
    expect(await ethers.provider.getBalance(turnupShares.address)).equal(
      contractBalance.add(expectedPrice).sub(protocolFee).sub(subjectFee)
    );
    expect(await turnupShares.sharesBalance(subject, subject)).to.equal(amount);
  });

  it("should allow users to buy shares", async function () {
    await init();
    const amount = 1; // example amount

    // owner buys shares

    let expectedPrice = await turnupShares.getBuyPriceAfterFee(subject, amount);
    await turnupShares.buyShares(subject, amount, {value: expectedPrice});

    // buyer buys shares

    let buyPrice = await turnupShares.getBuyPrice(subject, amount);
    let protocolFee = await turnupShares.getProtocolFee(buyPrice);
    let subjectFee = await turnupShares.getSubjectFee(buyPrice);
    expectedPrice = await turnupShares.getBuyPriceAfterFee(subject, amount);
    expect(expectedPrice).to.equal(buyPrice.add(protocolFee).add(subjectFee));

    let projectBalance = await ethers.provider.getBalance(project.address);
    let ownerBalance = await ethers.provider.getBalance(subject);
    let contractBalance = await ethers.provider.getBalance(turnupShares.address);
    let buyerBalance = await ethers.provider.getBalance(buyer.address);

    let gasCost = await executeAndReturnGasCost(turnupShares.connect(buyer).buyShares(subject, amount, {value: expectedPrice}));

    expect(await ethers.provider.getBalance(project.address)).equal(projectBalance.add(protocolFee));
    expect(await ethers.provider.getBalance(subject)).equal(ownerBalance.add(subjectFee));
    expect(await ethers.provider.getBalance(buyer.address)).equal(buyerBalance.sub(expectedPrice).sub(gasCost));
    expect(await ethers.provider.getBalance(turnupShares.address)).equal(
      contractBalance.add(expectedPrice).sub(protocolFee).sub(subjectFee)
    );
    expect(await turnupShares.sharesBalance(subject, buyer.address)).to.equal(amount);

    const amount2 = 3;
    buyPrice = await turnupShares.getBuyPrice(subject, amount2);
    protocolFee = await turnupShares.getProtocolFee(buyPrice);
    subjectFee = await turnupShares.getSubjectFee(buyPrice);
    expectedPrice = await turnupShares.getBuyPriceAfterFee(subject, amount2);

    projectBalance = await ethers.provider.getBalance(project.address);
    ownerBalance = await ethers.provider.getBalance(subject);
    contractBalance = await ethers.provider.getBalance(turnupShares.address);
    buyerBalance = await ethers.provider.getBalance(buyer.address);

    gasCost = await executeAndReturnGasCost(turnupShares.connect(buyer).buyShares(subject, amount2, {value: expectedPrice}));

    expect(await ethers.provider.getBalance(project.address)).equal(projectBalance.add(protocolFee));
    expect(await ethers.provider.getBalance(subject)).equal(ownerBalance.add(subjectFee));
    expect(await ethers.provider.getBalance(buyer.address)).equal(buyerBalance.sub(expectedPrice).sub(gasCost));
    expect(await ethers.provider.getBalance(turnupShares.address)).equal(
      contractBalance.add(expectedPrice).sub(protocolFee).sub(subjectFee)
    );
    expect(await turnupShares.sharesBalance(subject, buyer.address)).to.equal(amount + amount2);
  });

  it("should allow users to sell shares", async function () {
    await init();

    // owner buys keys

    let expectedPrice = await turnupShares.getBuyPriceAfterFee(subject, 4);
    await turnupShares.buyShares(subject, 4, {value: expectedPrice});

    // buyer buys keys

    expect(await turnupShares.sharesSupply(subject)).to.equal(4);

    const amountToBuy = 5;

    expect(await turnupShares.getBuyPrice(subject, amountToBuy)).equal("95000000000000000");

    expectedPrice = await turnupShares.getBuyPriceAfterFee(subject, amountToBuy);
    await turnupShares.connect(buyer).buyShares(subject, amountToBuy, {value: expectedPrice});
    expect(await turnupShares.sharesBalance(subject, buyer.address)).to.equal(amountToBuy);

    expect(await turnupShares.getSellPriceAfterFee(subject, 5)).equal("85500000000000000");
    expect(await ethers.provider.getBalance(turnupShares.address)).equal("102000000000000000");

    expect(await turnupShares.sharesSupply(subject)).to.equal(9);

    // Now buyer sells the shares.
    let amountToSell = 3;
    let sellPriceAfterFee = await turnupShares.getSellPriceAfterFee(subject, amountToSell);
    let sellPrice = await turnupShares.getSellPrice(subject, amountToSell);

    await expect(turnupShares.sellShares(subject, 4)).revertedWith("CannotSellLastKey()");

    let gasCost = await executeAndReturnGasCost(turnupShares.connect(buyer).sellShares(subject, amountToSell));

    await expect(turnupShares.connect(buyer).sellShares(subject, amountToSell)).revertedWith("InsufficientKeys()");

    amountToSell = 2;
    sellPrice = await turnupShares.getSellPrice(subject, amountToSell);
    sellPriceAfterFee = await turnupShares.getSellPriceAfterFee(subject, amountToSell);
    let protocolFee = await turnupShares.getProtocolFee(sellPrice);
    let subjectFee = await turnupShares.getSubjectFee(sellPrice);

    const projectBalance = await ethers.provider.getBalance(project.address);
    const ownerBalance = await ethers.provider.getBalance(subject);
    const contractBalance = await ethers.provider.getBalance(turnupShares.address);
    const buyerBalance = await ethers.provider.getBalance(buyer.address);

    gasCost = await executeAndReturnGasCost(turnupShares.connect(buyer).sellShares(subject, amountToSell));

    // Now let's check the final balances
    const finalOwnerBalance = await ethers.provider.getBalance(subject);
    const finalBuyerBalance = await ethers.provider.getBalance(buyer.address);
    const finalContractBalance = await ethers.provider.getBalance(turnupShares.address);
    const finalProjectBalance = await ethers.provider.getBalance(project.address);

    // since the owner is the seller and the subject, it would add(subjectFee) and subtract(subjectFee)
    expect(finalContractBalance).to.equal(contractBalance.sub(sellPrice));
    expect(finalProjectBalance).to.equal(projectBalance.add(protocolFee));
    expect(finalOwnerBalance).to.equal(ownerBalance.add(subjectFee));
    expect(finalBuyerBalance).to.equal(buyerBalance.add(sellPriceAfterFee).sub(gasCost));
  });

  it("should prevent non-owners from setting fee destination", async function () {
    await expect(turnupShares.connect(project).setFeeDestination(project.address)).to.be.revertedWith(
      "Ownable: caller is not the owner"
    );
  });

  it("should revert if getting selling price of not existent supply", async function () {
    await init();
    const amount = 1;
    await expect(turnupShares.getSellPrice(subject, amount)).revertedWith("InvalidAmount()");
  });

  it("should allow the owner to create a new wish pass", async function () {
    await init();
    const reservedQuantity = 10;
    await turnupShares.newWishPass(wished.address, reservedQuantity);
    const wishPass = await turnupShares.wishPasses(wished.address);

    expect(wishPass.owner).to.equal(wished.address);
    expect(wishPass.reservedQuantity).to.equal(reservedQuantity);
  });

  it("should prevent non-owners from upgrading the contract", async function () {
    const newImplementation = await ethers.getContractFactory("TurnupSharesV3");
    await expect(upgrades.upgradeProxy(turnupShares.address, newImplementation.connect(project))).to.be.revertedWith(
      "Ownable: caller is not the owner"
    );
  });
});
