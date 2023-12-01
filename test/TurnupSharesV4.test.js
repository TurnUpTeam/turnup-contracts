const {ethers, upgrades} = require("hardhat");
const {expect} = require("chai");
const DeployUtils = require("../scripts/lib/DeployUtils");

describe("TurnupSharesV4", function () {
  let turnupShares;
  let owner;
  let project;
  let buyer, buyer2, buyer3, wished, wished1, wished2, operator, dao, beneficiary;
  let subject;
  let wishSubject;

  const WISH = 0;
  const BIND = 1;
  const KEY = 2;
  const addr0 = "0x" + "0".repeat(40);

  const deployUtils = new DeployUtils(ethers);

  async function increaseBlockTimestampBy(offset) {
    await this.ethers.provider.send("evm_increaseTime", [offset]);
    await this.ethers.provider.send("evm_mine");
  }

  before(async function () {
    [owner, project, buyer, buyer2, buyer3, wished, wished1, wished2, operator, subject2, dao, beneficiary] =
      await ethers.getSigners();
    subject = owner.address;
    wishSubject = wished2.address;
  });

  beforeEach(async function () {
    turnupShares = await deployUtils.deployProxy("TurnupSharesV4");
    expect(await turnupShares.getVer()).to.equal("v5.0.0");
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

    // expect(await ethers.provider.getBalance(project.address)).equal(projectBalance.add(protocolFee));
    expect(await ethers.provider.getBalance(subject)).equal(ownerBalance.sub(expectedPrice).sub(gasCost).add(subjectFee));
    expect(await ethers.provider.getBalance(turnupShares.address)).equal(contractBalance.add(expectedPrice).sub(subjectFee));
    expect(await turnupShares.sharesBalance(subject, subject)).to.equal(amount);
  });

  it("should allow users to buy shares", async function () {
    await init();
    const amount = 1; // example amount

    // owner buys shares

    let buyPrice = await turnupShares.getBuyPrice(subject, amount);
    let expectedPrice = await turnupShares.getBuyPriceAfterFee(subject, amount);

    await expect(turnupShares.buyShares(subject, 0, {value: expectedPrice})).to.be.revertedWith("InvalidAmount()");

    await expect(turnupShares.buyShares(subject, amount, {value: expectedPrice}))
      .to.emit(turnupShares, "Trade") // Check if the Trade event is emitted
      .withArgs(subject, subject, true, amount, expectedPrice, amount, KEY);

    await expect(turnupShares.connect(operator).newWishPass(subject, 10)).to.be.revertedWith("CannotMakeASubjectAWish()");

    // buyer buys shares

    buyPrice = await turnupShares.getBuyPrice(subject, amount);
    let protocolFee = await turnupShares.getProtocolFee(buyPrice);
    let subjectFee = await turnupShares.getSubjectFee(buyPrice);
    expectedPrice = await turnupShares.getBuyPriceAfterFee(subject, amount);
    expect(expectedPrice).to.equal(buyPrice.add(protocolFee).add(subjectFee));

    let subjectBalanceBefore = await ethers.provider.getBalance(subject);
    let ownerBalance = await ethers.provider.getBalance(subject);
    let contractBalance = await ethers.provider.getBalance(turnupShares.address);
    let buyerBalance = await ethers.provider.getBalance(buyer.address);

    let gasCost = await executeAndReturnGasCost(turnupShares.connect(buyer).buyShares(subject, amount, {value: expectedPrice}));

    let subjectBalanceAfter = await ethers.provider.getBalance(subject);
    expect(subjectBalanceAfter).to.equal(subjectBalanceBefore.add(subjectFee));

    expect(await ethers.provider.getBalance(subject)).equal(ownerBalance.add(subjectFee));
    expect(await ethers.provider.getBalance(buyer.address)).equal(buyerBalance.sub(expectedPrice).sub(gasCost));
    expect(await ethers.provider.getBalance(turnupShares.address)).equal(contractBalance.add(expectedPrice).sub(subjectFee));
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

    expect(await ethers.provider.getBalance(subject)).equal(ownerBalance.add(subjectFee));
    expect(await ethers.provider.getBalance(buyer.address)).equal(buyerBalance.sub(expectedPrice).sub(gasCost));
    expect(await ethers.provider.getBalance(turnupShares.address)).equal(contractBalance.add(expectedPrice).sub(subjectFee));
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

    expect(await turnupShares.sharesSupply(subject)).to.equal(9);

    // Now buyer sells the shares.
    let amountToSell = 3;
    let sellPriceAfterFee = await turnupShares.getSellPriceAfterFee(subject, amountToSell);
    let sellPrice = await turnupShares.getSellPrice(subject, amountToSell);

    await expect(turnupShares.sellShares(subject, 4)).revertedWith("CannotSellLastKey()");

    let gasCost = await executeAndReturnGasCost(turnupShares.connect(buyer).sellShares(subject, amountToSell));

    const buyerShares = await turnupShares.sharesBalance(subject, buyer.address);

    await expect(turnupShares.connect(buyer).sellShares(subject, amountToSell)).revertedWith(
      `InsufficientKeys(${buyerShares})`
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

    // since the owner is the seller and the subject, it would add(subjectFee) and subtract(subjectFee)
    expect(finalContractBalance).to.equal(contractBalance.sub(sellPrice).add(protocolFee));
    expect(finalOwnerBalance).to.equal(ownerBalance.add(subjectFee));
    expect(finalBuyerBalance).to.equal(buyerBalance.add(sellPriceAfterFee).sub(gasCost));
  });

  it("should prevent non-owners from setting fee destination", async function () {
    await expect(turnupShares.connect(project).setFeeDestination(project.address)).to.be.revertedWith("Forbidden");
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
      .batchBuyShares([wished1.address, wished2.address], [wish1Amount, wish2Amount], [wish1Price, wish2Price], {
        value: wish1Price.add(wish2Price),
      });

    // Verify balances
    const wish1Balance = await turnupShares.getWishBalanceOf(wished1.address, buyer.address);
    expect(wish1Balance).to.equal(wish1Amount);

    const wish2Balance = await turnupShares.getWishBalanceOf(wished2.address, buyer.address);
    expect(wish2Balance).to.equal(wish2Amount);
  });

  it("should allow the owner to bind a wish pass to a subject", async function () {
    await init();

    let expectedPrice = await turnupShares.getBuyPriceAfterFee(subject2.address, 5);
    await turnupShares.connect(subject2).buyShares(subject2.address, 5, {value: expectedPrice});

    const reservedQuantity = 10;

    // Owner creates a new wish pass
    await expect(turnupShares.connect(operator).newWishPass(wished.address, reservedQuantity))
      .to.emit(turnupShares, "WishCreated")
      .withArgs(wished.address, reservedQuantity);
    await turnupShares.setFeeDestination(project.address);

    await expect(turnupShares.connect(operator).bindWishPass(wished.address, wished.address)).to.be.revertedWith(
      "SubjectCannotBeAWish()"
    );

    await expect(turnupShares.connect(operator).bindWishPass(subject2.address, wished.address)).to.be.revertedWith(
      "CannotMakeASubjectABind()"
    );

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
      .withArgs(buyer.address, wisher, true, amountToBuy, price, reservedQuantity + amountToBuy, WISH);

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
      .withArgs(buyer.address, authorizedSubject, true, amountToBuy, price, reservedQuantity + amountToBuy, BIND);

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
      .withArgs(sharesSubject, sharesSubject, true, reservedQuantity, buyPrice, reservedQuantity, BIND);

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

  it("should revert batch buying wrong amount", async function () {
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
    await expect(
      turnupShares.connect(buyer).batchBuyShares([wished1.address], [wish1Amount, wish2Amount], [wish1Price, wish2Price], {
        value: wish1Price.add(wish2Price),
      })
    ).to.be.revertedWith("WrongAmount()");
  });

  it("should revert batch too many keys", async function () {
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
    await expect(
      turnupShares
        .connect(buyer)
        .batchBuyShares(
          [
            wished1.address,
            wished1.address,
            wished1.address,
            wished1.address,
            wished1.address,
            wished1.address,
            wished1.address,
            wished1.address,
            wished1.address,
            wished1.address,
            wished1.address,
          ],
          [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
          [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
          {
            value: wish1Price.add(wish2Price),
          }
        )
    ).to.be.revertedWith("TooManyKeys()");
  });

  it("should revert new witch too large", async function () {
    await init();
    const reservedQty = 100;
    // Create wish passes
    await expect(turnupShares.connect(operator).newWishPass(wished1.address, reservedQty)).to.be.revertedWith(
      "ReserveQuantityTooLarge()"
    );
  });

  it("should revert when binding wrong wish", async function () {
    await init();
    const reservedQuantity = 10;

    // Owner creates a new wish pass
    await expect(turnupShares.connect(operator).newWishPass(wished.address, reservedQuantity))
      .to.emit(turnupShares, "WishCreated")
      .withArgs(wished.address, reservedQuantity);
    await turnupShares.setFeeDestination(project.address);

    // Owner binds the wish pass to a subject
    await expect(turnupShares.connect(operator).bindWishPass(buyer3.address, wished1.address)).to.be.revertedWith(
      "WishNotFound()"
    );
  });

  it("should revert when binding same wish", async function () {
    await init();
    const reservedQuantity = 10;
    // Owner creates a new wish pass
    await expect(turnupShares.connect(operator).newWishPass(wished.address, reservedQuantity))
      .to.emit(turnupShares, "WishCreated")
      .withArgs(wished.address, reservedQuantity);
    await turnupShares.setFeeDestination(project.address);

    // Owner binds the wish pass to a subject
    await turnupShares.connect(operator).bindWishPass(buyer3.address, wished.address);

    await expect(turnupShares.connect(operator).bindWishPass(buyer3.address, wished.address)).to.be.revertedWith(
      `WishAlreadyBound("${wished.address}")`
    );
  });

  it("should revert when claiming no wish", async function () {
    await init();
    const reservedQuantity = 10;
    const buyPrice = await turnupShares.getBuyPrice(ethers.constants.AddressZero, reservedQuantity);
    const protocolFee = await turnupShares.getProtocolFee(buyPrice);
    const subjectFee = await turnupShares.getSubjectFee(buyPrice);
    const totalPrice = buyPrice.add(protocolFee).add(subjectFee);

    // Owner creates a new wish pass
    await expect(turnupShares.connect(operator).newWishPass(wished.address, reservedQuantity))
      .to.emit(turnupShares, "WishCreated")
      .withArgs(wished.address, reservedQuantity);
    await turnupShares.setFeeDestination(project.address);

    await expect(turnupShares.connect(buyer3).claimReservedWishPass({value: totalPrice})).to.be.revertedWith("WishNotFound()");
  });

  it("should revert when not first key owner", async function () {
    await init();

    let expectedPrice = await turnupShares.getBuyPriceAfterFee(subject, 1);
    await expect(turnupShares.buyShares(buyer2.address, 1, {value: expectedPrice})).to.revertedWith(
      "OnlyKeysOwnerCanBuyFirstKey()"
    );
  });

  it("should revert when buying bound wish", async function () {
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

    await turnupShares.connect(operator).bindWishPass(buyer.address, wished.address);

    await expect(turnupShares.connect(buyer).buyShares(wisher, amountToBuy, {value: totalPrice})).to.revertedWith(
      "BoundCannotBeBuyOrSell()"
    );
  });

  it("should revert when selling last key", async function () {
    await init();
    const amountToBuy = 1;

    let expectedPrice = await turnupShares.getBuyPriceAfterFee(subject, amountToBuy);

    await expect(turnupShares.connect(buyer).sellShares(buyer.address, amountToBuy, {value: expectedPrice})).to.revertedWith(
      "CannotSellLastKey()"
    );
  });

  it("should revert batch buying wrong amount", async function () {
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
    await expect(
      turnupShares.connect(buyer).buyShares(wished1.address, wish1Amount, {
        value: wish1Price.sub(wish2Price),
      })
    ).to.be.revertedWith("TransactionFailedDueToPrice()");
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
    await turnupShares.getWishBalanceOf(authorizedSubject, subject);
  });

  it("should authorizedSubject sell key", async function () {
    await init();
    const amountToBuy = 5;
    const reservedQuantity = 10;
    const wisher = wished.address;
    const authorizedSubject = buyer2.address;

    // // Owner creates a new wish pass
    await turnupShares.connect(operator).newWishPass(wisher, reservedQuantity);
    //  // Owner binds the wish pass to an authorized subject
    await turnupShares.connect(operator).bindWishPass(authorizedSubject, wisher);
    // await turnupShares.getWishBalanceOf(authorizedSubject, subject)

    let expectedPrice = await turnupShares.getBuyPriceAfterFee(authorizedSubject, amountToBuy);

    await turnupShares.buyShares(authorizedSubject, amountToBuy, {value: expectedPrice});

    await turnupShares.sellShares(authorizedSubject, 1);
  });

  it("should allow users to buy and bind", async function () {
    await init();
    const amountToBuy = 5;
    const reservedQty = 10;
    const wishedAddress = buyer.address;
    await turnupShares.connect(operator).newWishPass(wishedAddress, reservedQty);
    let expectedPrice = await turnupShares.getBuyPriceAfterFee(wishedAddress, amountToBuy);

    await turnupShares.buyShares(wishedAddress, amountToBuy, {value: expectedPrice});
    await turnupShares.connect(operator).bindWishPass(buyer2.address, wishedAddress);
  });

  it("should revert when user buy and bind bad address", async function () {
    await init();
    const amountToBuy = 5;
    const reservedQty = 10;
    const wishedAddress = buyer.address;
    await turnupShares.connect(operator).newWishPass(wishedAddress, reservedQty);
    let expectedPrice = await turnupShares.getBuyPriceAfterFee(wishedAddress, amountToBuy);

    await turnupShares.buyShares(wishedAddress, amountToBuy, {value: expectedPrice});
    await expect(turnupShares.connect(operator).bindWishPass(turnupShares.address, wishedAddress)).to.revertedWith(
      "UnableToClaimReward()"
    );
  });

  it("should manage an expired wish that sold out", async function () {
    await init();
    const wisher = wished.address;

    // Owner creates a new wish pass
    await turnupShares.connect(operator).newWishPass(wisher, 10);

    // buyer buys 5
    let buyPrice = await turnupShares.getBuyPriceAfterFee(wisher, 5);
    await turnupShares.connect(buyer).buyShares(wisher, 5, {value: buyPrice});
    expect((await turnupShares.wishPasses(wisher)).totalSupply).to.equal(15);

    // buyer buys 4
    buyPrice = await turnupShares.getBuyPriceAfterFee(wisher, 4);
    await turnupShares.connect(buyer).buyShares(wisher, 4, {value: buyPrice});
    expect((await turnupShares.wishPasses(wisher)).totalSupply).to.equal(19);

    // buyer2 buys 12
    buyPrice = await turnupShares.getBuyPriceAfterFee(wisher, 12);
    await turnupShares.connect(buyer2).buyShares(wisher, 12, {value: buyPrice});
    expect((await turnupShares.wishPasses(wisher)).totalSupply).to.equal(31);

    // buyer sells 3
    await turnupShares.connect(buyer).sellShares(wisher, 3);
    expect((await turnupShares.wishPasses(wisher)).totalSupply).to.equal(28);

    // buyer3 buys 7
    buyPrice = await turnupShares.getBuyPriceAfterFee(wisher, 7);
    await turnupShares.connect(buyer3).buyShares(wisher, 7, {value: buyPrice});
    expect((await turnupShares.wishPasses(wisher)).totalSupply).to.equal(35);

    // buyer2 sells 1
    await turnupShares.connect(buyer2).sellShares(wisher, 1);
    expect((await turnupShares.wishPasses(wisher)).totalSupply).to.equal(34);

    expect(await turnupShares.getBalanceOf(wisher, buyer.address)).to.equal(6);
    expect(await turnupShares.getBalanceOf(wisher, buyer2.address)).to.equal(11);
    expect(await turnupShares.getBalanceOf(wisher, buyer3.address)).to.equal(7);

    // the wish expires
    await increaseBlockTimestampBy(90 * 24 * 60 * 60 + 1);

    buyPrice = await turnupShares.getBuyPriceAfterFee(wisher, 2);
    await expect(turnupShares.connect(buyer2).buyShares(wisher, 2, {value: buyPrice})).to.be.revertedWith(
      "ExpiredWishCanOnlyBeSold()"
    );

    // buyers sell everything
    await turnupShares.connect(buyer).sellShares(wisher, 6);
    expect((await turnupShares.wishPasses(wisher)).totalSupply).to.equal(28);
    await turnupShares.connect(buyer2).sellShares(wisher, 11);
    expect((await turnupShares.wishPasses(wisher)).totalSupply).to.equal(17);
    await turnupShares.connect(buyer3).sellShares(wisher, 7);
    expect((await turnupShares.wishPasses(wisher)).totalSupply).to.equal(10);

    // there is a remaining because of people buying and selling and buying again,
    // accumulating more rewards than what are returned back during the final sale
    expect((await turnupShares.wishPasses(wisher)).subjectReward).to.equal("184050000000000000");

    expect(await turnupShares.getBalanceOf(wisher, buyer.address)).to.equal(0);
    expect(await turnupShares.getBalanceOf(wisher, buyer2.address)).to.equal(0);
    expect(await turnupShares.getBalanceOf(wisher, buyer3.address)).to.equal(0);

    const whishStatus = await turnupShares.wishPasses(wisher);
    expect(whishStatus.subjectReward).to.equal("184050000000000000");
    expect(whishStatus.parkedFees).to.equal("490150000000000000");

    // the wish ends
    await increaseBlockTimestampBy(30 * 24 * 60 * 60 + 1);

    await expect(turnupShares.closeExpiredWish(wisher)).to.emit(turnupShares, "WishClosed").withArgs(wisher);

    expect(await turnupShares.DAOBalance()).to.equal("674200000000000000");
  });

  it("should manage an expired wish sale", async function () {
    await init();
    const wisher = wished.address;

    // Owner creates a new wish pass
    await turnupShares.connect(operator).newWishPass(wisher, 10);

    // buyer buys 5
    let buyPrice = await turnupShares.getBuyPriceAfterFee(wisher, 5);
    await turnupShares.connect(buyer).buyShares(wisher, 5, {value: buyPrice});

    // buyer buys 4
    buyPrice = await turnupShares.getBuyPriceAfterFee(wisher, 4);
    await turnupShares.connect(buyer).buyShares(wisher, 4, {value: buyPrice});

    // buyer2 buys 12
    buyPrice = await turnupShares.getBuyPriceAfterFee(wisher, 12);
    await turnupShares.connect(buyer2).buyShares(wisher, 12, {value: buyPrice});

    // buyer sells 3
    await turnupShares.connect(buyer).sellShares(wisher, 3);

    // buyer3 buys 7
    buyPrice = await turnupShares.getBuyPriceAfterFee(wisher, 7);
    await turnupShares.connect(buyer3).buyShares(wisher, 7, {value: buyPrice});

    // buyer2 sells 1
    await turnupShares.connect(buyer2).sellShares(wisher, 1);

    expect(await turnupShares.getBalanceOf(wisher, buyer.address)).to.equal(6);
    expect(await turnupShares.getBalanceOf(wisher, buyer2.address)).to.equal(11);
    expect(await turnupShares.getBalanceOf(wisher, buyer3.address)).to.equal(7);

    // the wish expires
    await increaseBlockTimestampBy(90 * 24 * 60 * 60 + 1);

    buyPrice = await turnupShares.getBuyPriceAfterFee(wisher, 2);
    await expect(turnupShares.connect(buyer2).buyShares(wisher, 2, {value: buyPrice})).to.be.revertedWith(
      "ExpiredWishCanOnlyBeSold()"
    );

    // buyer sells 4
    await turnupShares.connect(buyer).sellShares(wisher, 6);

    // buyer2 sells 8
    await turnupShares.connect(buyer2).sellShares(wisher, 8);

    // buyer3 sells 4
    await turnupShares.connect(buyer3).sellShares(wisher, 4);

    expect(await turnupShares.getBalanceOf(wisher, buyer.address)).to.equal(0);
    expect(await turnupShares.getBalanceOf(wisher, buyer2.address)).to.equal(3);
    expect(await turnupShares.getBalanceOf(wisher, buyer3.address)).to.equal(3);

    await expect(turnupShares.closeExpiredWish(wisher)).to.be.revertedWith("WishNotExpiredYet()");

    // the wish ends
    await increaseBlockTimestampBy(30 * 24 * 60 * 60 + 1);

    await expect(turnupShares.connect(buyer2).sellShares(wisher, 1)).to.be.revertedWith("GracePeriodExpired()");

    await expect(turnupShares.withdrawDAOFunds(0, addr0)).to.be.revertedWith("DAONotSetup()");

    await expect(turnupShares.setDAO(dao.address)).to.emit(turnupShares, "DAOUpdated").withArgs(dao.address);

    await expect(turnupShares.connect(dao).withdrawDAOFunds(0, addr0)).to.be.revertedWith("InsufficientFunds()");

    expect(await turnupShares.DAOBalance()).to.equal(0);

    await expect(turnupShares.connect(dao).closeExpiredWish(wisher)).to.emit(turnupShares, "WishClosed").withArgs(wisher);

    expect(await turnupShares.DAOBalance()).to.equal("1175575000000000000");

    let balanceBefore = await ethers.provider.getBalance(beneficiary.address);
    await turnupShares.connect(dao).withdrawDAOFunds(0, beneficiary.address);
    let balanceAfter = await ethers.provider.getBalance(beneficiary.address);
    expect(balanceAfter.sub(balanceBefore).toString()).to.equal("1175575000000000000");
  });
});
