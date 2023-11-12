const {ethers, upgrades} = require("hardhat");
const {expect} = require("chai");
const DeployUtils = require("../scripts/lib/DeployUtils");

describe("TurnupSharesV4", function () {
  let turnupShares;
  let owner;
  let project;
  let buyer, buyer2, buyer3, wished, wished1, wished2, operator;
  let subject;
  let wishSubject;

  const WISH = 0;
  const BIND = 1;
  const KEY = 2;

  const deployUtils = new DeployUtils(ethers);

  before(async function () {
    [owner, project, buyer, buyer2, buyer3, wished, wished1, wished2, operator] = await ethers.getSigners();
    subject = owner.address;
    wishSubject = wished2.address;
  });

  beforeEach(async function () {
    turnupShares = await deployUtils.deployProxy("TurnupSharesV4");
    expect(await turnupShares.getVer()).to.equal("v4.2.0");
  });

  async function init() {
    await turnupShares.setFeeDestination(project.address);
    const protocolFee = ethers.utils.parseUnits("50000000", "gwei"); // example fee
    await turnupShares.setProtocolFeePercent(protocolFee);
    const subjectFee = ethers.utils.parseUnits("50000000", "gwei"); // example fee
    await turnupShares.setSubjectFeePercent(subjectFee);
    await expect(turnupShares.newWishPass(wished.address, 1)).revertedWith("OperatorNotSet()");
    await turnupShares.setOperator(operator.address);
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
    await expect(turnupShares.setFeeDestination(project.address))
      .to.emit(turnupShares, "ProtocolFeeDestinationUpdated")
      .withArgs(project.address);
    expect(await turnupShares.protocolFeeDestination()).to.equal(project.address);
  });

  it("should allow the owner to set protocol fee percent", async function () {
    const protocolFee = ethers.utils.parseUnits("5", "wei"); // example fee
    await expect(turnupShares.setProtocolFeePercent(protocolFee))
      .to.emit(turnupShares, "ProtocolFeePercentUpdated")
      .withArgs(protocolFee);
    expect(await turnupShares.protocolFeePercent()).to.equal(protocolFee);
  });

  it("should allow the owner to set subject fee percent", async function () {
    const subjectFee = ethers.utils.parseUnits("5", "wei"); // example fee
    await expect(turnupShares.setSubjectFeePercent(subjectFee))
      .to.emit(turnupShares, "SubjectFeePercentUpdated")
      .withArgs(subjectFee);
    expect(await turnupShares.subjectFeePercent()).to.equal(subjectFee);
  });

  it("should show that the price is consistent", async function () {
    await init();

    // owner buys shares

    let expectedPrice = await turnupShares.getBuyPriceAfterFee(subject, 1);
    await turnupShares.buyShares(subject, 1, {value: expectedPrice});

    const amount = ethers.BigNumber.from("10");

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

    let buyPrice = await turnupShares.getBuyPrice(subject, amount);
    let protocolFee = await turnupShares.getProtocolFee(buyPrice);
    let subjectFee = await turnupShares.getSubjectFee(buyPrice);
    let expectedPrice = await turnupShares.getBuyPriceAfterFee(subject, amount);

    await expect(turnupShares.buyShares(subject, amount, {value: expectedPrice}))
      .to.emit(turnupShares, "Trade") // Check if the Trade event is emitted
      .withArgs(subject, subject, true, amount, expectedPrice, protocolFee, subjectFee, amount, KEY);

    // buyer buys shares

    buyPrice = await turnupShares.getBuyPrice(subject, amount);
    protocolFee = await turnupShares.getProtocolFee(buyPrice);
    subjectFee = await turnupShares.getSubjectFee(buyPrice);
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

    const buyerShares = await turnupShares.sharesBalance(subject, buyer.address);

    await expect(turnupShares.connect(buyer).sellShares(subject, amountToSell)).revertedWith(
      `InsufficientKeys("${buyer.address}", "${subject}", ${buyerShares}, ${amountToSell})`
    );

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
    await turnupShares.connect(operator).newWishPass(wished.address, reservedQuantity);
    const wishPass = await turnupShares.wishPasses(wished.address);

    expect(wishPass.owner).to.equal(wished.address);
    expect(wishPass.reservedQuantity).to.equal(reservedQuantity);
  });

  it("should prevent non-owners from upgrading the contract", async function () {
    const newImplementation = await ethers.getContractFactory("TurnupSharesV4");
    await expect(upgrades.upgradeProxy(turnupShares.address, newImplementation.connect(project))).to.be.revertedWith(
      "Ownable: caller is not the owner"
    );
  });

  it("should allow users to buy and sell wishes", async function () {
    await init();
    // Owner creates wish pass
    const reservedQty = 10;
    await turnupShares.connect(operator).newWishPass(wished.address, reservedQty);

    // Buyer purchases some wish pass shares
    const buyAmount = 5;
    const buyPrice = await turnupShares.getBuyPriceAfterFee(wished.address, buyAmount);
    await turnupShares.connect(buyer).buyShares(wished.address, buyAmount, {value: buyPrice});

    expect((await turnupShares.wishPasses(wished.address)).totalSupply.toNumber()).to.equal(15);

    expect(await turnupShares.getWishBalanceOf(wished.address, buyer.address)).to.equal(buyAmount);
    // Verify buyer wish pass balance

    // Buyer sells some wish pass shares
    const sellAmount = 2;
    const sellPrice = await turnupShares.getSellPriceAfterFee(wished.address, sellAmount);

    await turnupShares.connect(buyer).sellShares(wished.address, sellAmount);

    expect(await turnupShares.getWishBalanceOf(wished.address, buyer.address)).to.equal(buyAmount - sellAmount);
  });

  it("should allow batch buying multiple wish passes", async function () {
    await init();
    // Create 2 wish passes
    const reservedQty = 10;
    await turnupShares.connect(operator).newWishPass(wished1.address, reservedQty);
    await turnupShares.connect(operator).newWishPass(wished2.address, reservedQty);

    // Get batch buy prices
    const wish1Amount = 5;
    const wish2Amount = 3;
    const wish1Price = await turnupShares.getBuyPriceAfterFee(wished1.address, wish1Amount);
    const wish2Price = await turnupShares.getBuyPriceAfterFee(wished2.address, wish2Amount);

    // Batch buy
    await turnupShares
      .connect(buyer)
      .batchBuyShares([wished1.address, wished2.address], [wish1Amount, wish2Amount], {value: wish1Price.add(wish2Price)});

    // Verify balances
    const wish1Balance = await turnupShares.getWishBalanceOf(wished1.address, buyer.address);
    expect(wish1Balance).to.equal(wish1Amount);

    const wish2Balance = await turnupShares.getWishBalanceOf(wished2.address, buyer.address);
    expect(wish2Balance).to.equal(wish2Amount);
  });

  it("should allow the owner to bind a wish pass to a subject", async function () {
    await init();
    const reservedQuantity = 10;

    // Owner creates a new wish pass
    await expect(turnupShares.connect(operator).newWishPass(wished.address, reservedQuantity))
      .to.emit(turnupShares, "WishCreated")
      .withArgs(wished.address, reservedQuantity);
    await turnupShares.setFeeDestination(project.address);

    // Owner binds the wish pass to a subject
    await expect(turnupShares.connect(operator).bindWishPass(subject, wished.address))
      .to.emit(turnupShares, "WishBound")
      .withArgs(subject, wished.address);

    // Check if the wish pass has been bound correctly
    expect(await turnupShares.authorizedWishes(subject)).to.equal(wished.address);
    const wishPass = await turnupShares.wishPasses(wished.address);
    expect(wishPass.subject).to.equal(subject);
  });

  it("should revert if a non-operator tries to bind a wish pass, included the owner", async function () {
    await init();
    const reservedQuantity = 10;

    // operator creates a new wish pass
    await turnupShares.connect(operator).newWishPass(wished.address, reservedQuantity);

    // Owner tries to bind the wish pass
    await expect(turnupShares.bindWishPass(subject, wished.address)).to.be.revertedWith("NotTheOperator()");

    // Non-operator tries to bind the wish pass
    await expect(turnupShares.connect(buyer).bindWishPass(subject, wished.address)).to.be.revertedWith("NotTheOperator()");
  });

  it("should revert if trying to bind a wish pass that has already been bound", async function () {
    await init();
    const reservedQuantity = 10;

    // Owner creates a new wish pass and binds it
    await turnupShares.connect(operator).newWishPass(wished.address, reservedQuantity);
    await turnupShares.connect(operator).bindWishPass(subject, wished.address);

    // Try to bind the same wish pass again
    await expect(turnupShares.connect(operator).bindWishPass(subject, wished.address)).to.be.revertedWith(
      `WishAlreadyBound("${wished.address}")`
    );
  });

  it("should revert if the subject or wisher address is zero", async function () {
    await init();
    const reservedQuantity = 10;

    // Owner creates a new wish pass
    await turnupShares.connect(operator).newWishPass(wished.address, reservedQuantity);

    // Attempt to bind with a zero subject address
    await expect(turnupShares.connect(operator).bindWishPass(ethers.constants.AddressZero, wished.address)).to.be.revertedWith(
      "InvalidZeroAddress()"
    );

    // Attempt to bind with a zero wisher address
    await expect(turnupShares.connect(operator).bindWishPass(subject, ethers.constants.AddressZero)).to.be.revertedWith(
      "InvalidZeroAddress()"
    );
  });

  it("should allow users to buy wish shares", async function () {
    await init();
    const reservedQuantity = 10;
    const amountToBuy = 5;
    const wisher = wished.address;

    // Owner creates a new wish pass
    await turnupShares.connect(operator).newWishPass(wisher, reservedQuantity);

    // Calculate the expected price for buying the wish shares
    const price = await turnupShares.getBuyPrice(wisher, amountToBuy);
    const protocolFee = await turnupShares.getProtocolFee(price);
    const subjectFee = await turnupShares.getSubjectFee(price);
    const totalPrice = price.add(protocolFee).add(subjectFee);

    // User buys wish shares
    await expect(turnupShares.connect(buyer).buyShares(wisher, amountToBuy, {value: totalPrice}))
      .to.emit(turnupShares, "Trade") // Check if the Trade event is emitted
      .withArgs(buyer.address, wisher, true, amountToBuy, price, protocolFee, subjectFee, reservedQuantity + amountToBuy, WISH);

    // Check the new total supply and balance for the wisher
    expect((await turnupShares.wishPasses(wisher)).totalSupply).to.equal(reservedQuantity + amountToBuy);
    expect(await turnupShares.getWishBalanceOf(wisher, buyer.address)).to.equal(amountToBuy);
  });

  it("should allow users to buy authorized wish shares", async function () {
    await init();
    const reservedQuantity = 10;
    const amountToBuy = 5;
    const wisher = wished.address;
    const authorizedSubject = buyer2.address;

    // Owner creates a new wish pass
    await turnupShares.connect(operator).newWishPass(wisher, reservedQuantity);
    // Owner binds the wish pass to an authorized subject
    await turnupShares.connect(operator).bindWishPass(authorizedSubject, wisher);

    // Calculate the expected price for buying the authorized wish shares
    const price = await turnupShares.getBuyPrice(authorizedSubject, amountToBuy);
    const protocolFee = await turnupShares.getProtocolFee(price);
    const subjectFee = await turnupShares.getSubjectFee(price);
    const totalPrice = price.add(protocolFee).add(subjectFee);

    // User buys authorized wish shares
    await expect(turnupShares.connect(buyer).buyShares(authorizedSubject, amountToBuy, {value: totalPrice}))
      .to.emit(turnupShares, "Trade") // Check if the Trade event is emitted
      .withArgs(
        buyer.address,
        authorizedSubject,
        true,
        amountToBuy,
        price,
        protocolFee,
        subjectFee,
        reservedQuantity + amountToBuy,
        BIND
      );

    // Check the new total supply and balance for the authorized subject
    expect((await turnupShares.wishPasses(wisher)).totalSupply).to.equal(reservedQuantity + amountToBuy);
    expect(await turnupShares.getWishBalanceOf(wisher, buyer.address)).to.equal(amountToBuy);
  });

  it("should allow a wisher to claim their reserved wish pass", async function () {
    await init();
    const reservedQuantity = 10;

    const sharesSubject = buyer3.address;

    // Owner creates a new wish pass for the 'wished' address
    await turnupShares.connect(operator).newWishPass(wished.address, reservedQuantity);

    // Owner binds the wish pass to the 'wished' address
    await turnupShares.connect(operator).bindWishPass(sharesSubject, wished.address);

    // Calculate the expected price for claiming the wish pass
    const buyPrice = await turnupShares.getBuyPrice(ethers.constants.AddressZero, reservedQuantity);
    const protocolFee = await turnupShares.getProtocolFee(buyPrice);
    const subjectFee = await turnupShares.getSubjectFee(buyPrice);
    const totalPrice = buyPrice.add(protocolFee).add(subjectFee);

    expect((await turnupShares.wishPasses(wished.address)).reservedQuantity).to.equal(reservedQuantity);

    // Simulate the 'wished' address claiming the reserved wish pass by sending the correct total price
    const tx = await turnupShares.connect(buyer3).claimReservedWishPass({value: totalPrice});

    // Expect the Trade event to be emitted with correct parameters
    await expect(tx)
      .to.emit(turnupShares, "Trade")
      .withArgs(
        sharesSubject,
        sharesSubject,
        true,
        reservedQuantity,
        buyPrice,
        protocolFee,
        subjectFee,
        reservedQuantity,
        BIND
      );

    // Check if the wish pass balance of the 'wished' address is updated correctly
    let balance = await turnupShares.getWishBalanceOf(sharesSubject, wished.address);
    expect(balance).to.equal(0);

    // Check if the reserved quantity for the 'wished' address is set to 0 after claiming
    const wishPass = await turnupShares.wishPasses(wished.address);
    expect((await turnupShares.wishPasses(wished.address)).reservedQuantity).to.equal(0);
  });

  it("should be upgradeable by the owner", async function () {
    const Upgraded = await ethers.getContractFactory("TurnupSharesV4b");
    const upgraded = await upgrades.upgradeProxy(turnupShares.address, Upgraded);

    expect(await upgraded.getVer()).to.equal("v7.0.0");
  });

  it("should prevent non-owners from upgrading the contract", async function () {
    const Upgraded = await ethers.getContractFactory("TurnupSharesV4b");

    await expect(upgrades.upgradeProxy(turnupShares.address, Upgraded.connect(buyer))).to.be.revertedWith(
      "Ownable: caller is not the owner"
    );
  });
});
