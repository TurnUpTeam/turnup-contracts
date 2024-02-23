const {expect} = require("chai");

const EthDeployUtils = require("eth-deploy-utils");
const deployUtils = new EthDeployUtils();

const {getTimestamp, increaseBlockTimestampBy, cl, addr0} = require("./helpers");
const {ethers} = require("hardhat");

describe("PFPAuction", function () {
  let auction;
  let lfg;
  // three pfp collections
  let owls, rats, pigs, dogs;
  const priceLfg = ethers.utils.parseEther("100");
  const priceMatic = ethers.utils.parseEther("200");
  let tenThousand = ethers.utils.parseEther("10000");
  let owner, bob, alice, fred, jim, jane;
  let tenHours = 36000;

  before(async function () {
    [owner, bob, alice, fred, jim, jane] = await ethers.getSigners();
  });

  async function initAndDeploy() {
    let maxSupply = ethers.utils.parseEther("3000000000");
    let initialSupply = ethers.utils.parseEther("900000000");
    let amountReservedToPool = ethers.utils.parseEther("300000000");
    let amountReservedToSharesPool = ethers.utils.parseEther("200000000");

    lfg = await deployUtils.deployProxy(
      "LFGToken",
      owner.address,
      maxSupply,
      initialSupply,
      amountReservedToPool,
      amountReservedToSharesPool
    );

    owls = await deployUtils.deployProxy("TurnUPNFT", "TurnUP Owls", "TOWLS", "https://meta.turnup.so/owls/");
    rats = await deployUtils.deployProxy("TurnUPNFT", "TurnUP Rats", "TRATS", "https://meta.turnup.so/rats/");
    pigs = await deployUtils.deployProxy("TurnUPNFT", "TurnUP Pigs", "TPIGS", "https://meta.turnup.so/pigs/");
    dogs = await deployUtils.deployProxy("TurnUPNFT", "TurnUP Dogs", "TDOGS", "https://meta.turnup.so/dogs/");

    auction = await deployUtils.deployProxy("PFPAuction", lfg.address);

    await expect(owls.preMint(auction.address, 20))
      .to.emit(owls, "Transfer")
      .withArgs(addr0, auction.address, 1)
      .to.emit(owls, "Transfer")
      .withArgs(addr0, auction.address, 20);

    await expect(owls.preMint(auction.address, 20))
      .to.emit(owls, "Transfer")
      .withArgs(addr0, auction.address, 21)
      .to.emit(owls, "Transfer")
      .withArgs(addr0, auction.address, 40);
    await owls.preMint(auction.address, 20);
    await owls.preMint(auction.address, 20);
    await owls.preMint(auction.address, 20);
    await owls.preMint(owner.address, 20);

    await rats.preMint(auction.address, 20);
    await rats.preMint(auction.address, 20);
    await rats.preMint(auction.address, 10);

    await pigs.preMint(owner.address, 20);

    await dogs.preMint(auction.address, 20);
  }

  beforeEach(async function () {
    await initAndDeploy();

    await lfg.transfer(bob.address, tenThousand);
    await lfg.transfer(alice.address, tenThousand);
    await lfg.transfer(fred.address, tenThousand);
    await lfg.transfer(jim.address, tenThousand);
    await lfg.transfer(jane.address, tenThousand);
  });

  async function ts() {
    return (await getTimestamp()) + 1;
  }

  it("should allow to batch bid", async function () {
    let id = 1;
    let id2 = 2;
    let id3 = 3;

    let startTime = BigInt(await ts());
    let endTime = BigInt(startTime + 3600n * 8n);
    let deferredDuration = 3600n; // 2 hours
    let encodedTiming = startTime + (endTime << 32n) + (deferredDuration << 64n);

    await auction.setItemsForAuction(
      [rats.address, owls.address, dogs.address, rats.address],
      [id, id2, id3, id2],
      [priceMatic, priceLfg, priceMatic, priceMatic],
      [true, false, true, true],
      [encodedTiming, encodedTiming, encodedTiming, encodedTiming]
    );

    let ratsPrice = await auction.getNextPrice(rats.address, id);
    let owlsPrice = await auction.getNextPrice(owls.address, id2);
    let dogsPrice = await auction.getNextPrice(dogs.address, id3);
    let previousDogPrice = dogsPrice;

    // bob makes a batch bid

    let lfgBalanceBefore = await lfg.balanceOf(bob.address);
    await lfg.connect(bob).approve(auction.address, owlsPrice.add(1000000));
    // successful bid
    let balanceBefore = await ethers.provider.getBalance(bob.address);
    await auction
      .connect(bob)
      .bidBatch([rats.address, owls.address, dogs.address], [id, id2, id3], [ratsPrice, owlsPrice, dogsPrice], {
        value: ratsPrice.add(owlsPrice).add(dogsPrice),
      });
    // notice that owls are paid in LFG, so there is an extra value sent to the contract
    let lfgBalanceAfter = await lfg.balanceOf(bob.address);
    let balanceAfter = await ethers.provider.getBalance(bob.address);

    expect(lfgBalanceBefore.sub(lfgBalanceAfter)).to.equal(owlsPrice);

    const dec = "1000000000000000000";
    // it just spends some extra gas
    expect(balanceBefore.sub(balanceAfter).div(dec)).to.equal(priceMatic.mul(2).div(dec));
    // all bids have been successful
    expect((await auction.getNextPrice(rats.address, id)).div(dec).toNumber()).greaterThan(ratsPrice.div(dec).toNumber());
    expect((await auction.getNextPrice(owls.address, id2)).div(dec).toNumber()).greaterThan(owlsPrice.div(dec).toNumber());
    expect((await auction.getNextPrice(dogs.address, id3)).div(dec).toNumber()).greaterThan(dogsPrice.div(dec).toNumber());

    // alice makes a batch bid
    // passing insufficient funds

    let previousRatsPrice = ratsPrice;
    ratsPrice = await auction.getNextPrice(rats.address, id);
    let ratsPrice2 = await auction.getNextPrice(rats.address, id2);

    balanceBefore = await ethers.provider.getBalance(alice.address);

    await auction
      .connect(alice)
      .bidBatch([rats.address, rats.address], [id, id2], [ratsPrice, ratsPrice2], {value: ratsPrice.mul(3).div(2)});

    expect((await auction.getNextPrice(rats.address, id)).div(dec).toNumber()).greaterThan(
      previousRatsPrice.div(dec).toNumber()
    );
    // the second bid failed
    expect(await auction.getNextPrice(rats.address, id2)).equal(ratsPrice2);

    balanceAfter = await ethers.provider.getBalance(alice.address);

    expect(balanceBefore.sub(balanceAfter).div(dec)).to.equal(ratsPrice.div(dec));

    // fred makes a batch bid
    // passing insufficient spending amount
    ratsPrice = await auction.getNextPrice(rats.address, id2);
    dogsPrice = await auction.getNextPrice(dogs.address, id3);
    let fee = await auction.getFee(dogs.address, id3);
    let t = await ts();

    await expect(
      auction
        .connect(fred)
        .bidBatch([rats.address, dogs.address], [id2, id3], [ratsPrice.div(2), dogsPrice], {value: ratsPrice.add(dogsPrice)})
    )
      .emit(auction, "Bid")
      .withArgs(dogs.address, id3, dogsPrice, t, fred.address, t + 28796, previousDogPrice, bob.address, dogsPrice.sub(fee))
      .emit(auction, "BidFailed")
      .withArgs(rats.address, id2, ratsPrice, fred.address);

    // the first bid failed
    expect(await auction.getNextPrice(rats.address, id2)).equal(ratsPrice);
    // the second bit succeeded
    expect((await auction.getNextPrice(dogs.address, id3)).div(dec).toNumber()).greaterThan(dogsPrice.div(dec).toNumber());

    balanceAfter = await ethers.provider.getBalance(fred.address);

    expect(balanceBefore.sub(balanceAfter).div(dec)).to.equal(dogsPrice.div(dec));
  });

  it("should make many batch bid without going out of gas", async function () {
    await lfg.transfer(bob.address, tenThousand.mul(100));

    let startTime = BigInt(await ts());
    let endTime = BigInt(startTime + 3600n * 8n);
    let deferredDuration = 3600n; // 2 hours
    let encodedTiming = startTime + (endTime << 32n) + (deferredDuration << 64n);

    const tokens = [];
    for (let i = 0; i < 30; i++) {
      let newToken = await deployUtils.deployProxy(
        "TurnUPNFT",
        "TurnUP Token" + i,
        "T" + i,
        "https://meta.turnup.so/t" + i + "/"
      );
      await newToken.preMint(auction.address, 1);
      await auction.setItemsForAuction([newToken.address], [1], [priceLfg], [false], [encodedTiming]);
      tokens.push(newToken);
    }
    await lfg.connect(bob).approve(auction.address, priceLfg.mul(30));

    const tx = await auction.connect(bob).bidBatch(
      tokens.map((t) => t.address),
      tokens.map((t) => 1),
      tokens.map((t) => priceLfg),
      {value: priceLfg.mul(30)}
    );
    const receipt = await tx.wait();
    const bidEvents = receipt.events.filter((event) => event.event === "Bid");
    expect(bidEvents.length).to.equal(30);
  });

  it("should allow to bid multiple times over LFG and MATIC paid owls", async function () {
    // owls #1
    let id = 1;
    let startTime = BigInt(await ts());
    // ten hours
    let endTime = BigInt(startTime + 3600n * 10n);
    let deferredDuration = 3600n; // 1 hours
    let encodedTiming = startTime + (endTime << 32n) + (deferredDuration << 64n);

    await expect(auction.setItemForAuction(owls.address, id, priceLfg, false, encodedTiming))
      .to.emit(auction, "ItemForAuction")
      .withArgs(owls.address, id, priceLfg, false, startTime, endTime, deferredDuration);

    let owlsInitialPrice = await auction.getNextPrice(owls.address, 1);
    let item = await auction.getItem(owls.address, id);
    expect(item.bidder).to.equal(addr0);
    let owlsCoin = item.native ? "MATIC" : "LFG";

    expect(owlsInitialPrice).to.equal(priceLfg);
    expect(owlsCoin).to.equal("LFG");

    // failing bids
    await expect(auction.connect(bob).bid(owls.address, 110)).to.be.revertedWith("AssetNotFound()");
    await expect(auction.connect(bob).bid(owls.address, 200)).to.be.revertedWith("ERC721: invalid token ID");

    // unapproved bid
    await expect(auction.connect(bob).bid(owls.address, id)).to.be.revertedWith("ERC20: insufficient allowance");

    // bob approves LFG
    await expect(lfg.connect(bob).approve(auction.address, owlsInitialPrice))
      .to.emit(lfg, "Approval")
      .withArgs(bob.address, auction.address, owlsInitialPrice);

    const endTimeBefore = await auction.auctionEndTime(owls.address, id);

    // after 8 hours
    await increaseBlockTimestampBy(3600 * 8);

    let t = await ts();
    // successful bid
    let price = await auction.getNextPrice(owls.address, id);
    let fee = await auction.getFee(owls.address, id);
    await expect(auction.connect(bob).bid(owls.address, id))
      .to.emit(auction, "Bid")
      .withArgs(owls.address, id, owlsInitialPrice, await ts(), bob.address, t + 7195, 0, addr0, price.sub(fee));

    let endTimeAfter = await auction.auctionEndTime(owls.address, id);

    expect(endTimeAfter).to.equal(endTimeBefore);

    item = await auction.getItem(owls.address, id);
    expect(item.bidder).to.equal(bob.address);

    let previousPrice = price;
    // raising price
    price = await auction.getNextPrice(owls.address, id);
    expect(price).to.equal(owlsInitialPrice.add(owlsInitialPrice.mul(10).div(100)));

    fee = await auction.getFee(owls.address, id);
    let totalFee = owlsInitialPrice.add(fee);

    // alice approves lfg
    await lfg.connect(alice).approve(auction.address, price.mul(10));

    await increaseBlockTimestampBy(Math.round(3600 * 1.6));

    // alice bids
    t = await ts();
    await expect(auction.connect(alice).bid(owls.address, id))
      .to.emit(auction, "Bid")
      .withArgs(owls.address, id, price, await ts(), alice.address, t + 3600, previousPrice, bob.address, price.sub(fee))
      .to.emit(lfg, "Transfer")
      .withArgs(auction.address, bob.address, price.sub(fee));

    let item2 = await auction.getItem(owls.address, id);
    endTimeAfter = await auction.auctionEndTime(owls.address, id);
    expect(endTimeAfter).to.equal(item2.bidAt + Number(deferredDuration));

    previousPrice = price;
    // alice bids again
    price = await auction.getNextPrice(owls.address, id);
    fee = await auction.getFee(owls.address, id);
    totalFee = totalFee.add(fee);
    t = await ts();
    await expect(auction.connect(alice).bid(owls.address, id))
      .to.emit(auction, "Bid")
      .withArgs(owls.address, id, price, await ts(), alice.address, t + 3600, previousPrice, alice.address, price.sub(fee))
      .to.emit(lfg, "Transfer")
      .withArgs(auction.address, alice.address, price.sub(fee));

    await expect(auction.connect(alice).claim(owls.address, id)).to.be.revertedWith("AuctionIsNotOver()");

    let now = await ts();
    endTime = await auction.auctionEndTime(owls.address, id);

    // an hour passes
    await increaseBlockTimestampBy(endTime - now + 1);

    // bob tries to bid again but auction is over
    await expect(auction.connect(bob).bid(owls.address, id)).to.be.revertedWith("AuctionIsOver()");

    await expect(auction.connect(fred).claim(owls.address, id)).to.be.revertedWith("NotTheWinner()");

    await expect(auction.connect(alice).claim(owls.address, id))
      .to.emit(owls, "Transfer")
      .withArgs(auction.address, alice.address, id)
      .to.emit(auction, "Claim")
      .withArgs(owls.address, id, alice.address, price);

    expect(await lfg.balanceOf(auction.address)).to.equal(totalFee);

    // owls # 2
    id = 2;

    startTime = BigInt(await ts());
    // twelve hours
    endTime = BigInt(startTime + 3600n * 12n);
    deferredDuration = 2n * 3600n; // 2 hours
    encodedTiming = startTime + (endTime << 32n) + (deferredDuration << 64n);

    await expect(auction.setItemForAuction(owls.address, id, priceMatic, true, encodedTiming))
      .to.emit(auction, "ItemForAuction")
      .withArgs(owls.address, id, priceMatic, true, startTime, endTime, deferredDuration);

    // bob approves LFG and bids
    await expect(lfg.connect(bob).approve(auction.address, owlsInitialPrice))
      .to.emit(lfg, "Approval")
      .withArgs(bob.address, auction.address, owlsInitialPrice);

    await expect(auction.connect(bob).bid(owls.address, id, {value: priceMatic})).to.emit(auction, "Bid");
    // nobody beats the bid, an hour passes
    await increaseBlockTimestampBy(3600 * 20);

    await expect(auction.connect(bob).claim(owls.address, id))
      .to.emit(owls, "Transfer")
      .withArgs(auction.address, bob.address, id);
  });

  it("should allow to bid multiple times over MATIC paid rats", async function () {
    let id = 1;
    let startTime = BigInt(await ts());
    let endTime = BigInt(startTime + 3600n * 8n);
    let deferredDuration = 3600n; // 2 hours
    let encodedTiming = startTime + (endTime << 32n) + (deferredDuration << 64n);
    let startTime2 = BigInt(await ts());
    // twelve hours
    let endTime2 = BigInt(startTime2 + 3600n * 12n);
    let deferredDuration2 = 2n * 3600n; // 2 hours
    let encodedTiming2 = startTime2 + (endTime2 << 32n) + (deferredDuration2 << 64n);
    await expect(
      auction.setItemsForAuction(
        [rats.address, owls.address],
        [id, id],
        [priceMatic, priceLfg],
        [true, false],
        [encodedTiming, encodedTiming2]
      )
    )
      .to.emit(auction, "ItemForAuction")
      .withArgs(rats.address, id, priceMatic, true, startTime, endTime, deferredDuration)
      .to.emit(auction, "ItemForAuction")
      .withArgs(owls.address, id, priceLfg, false, startTime2, endTime2, deferredDuration2);

    let ratsInitialPrice = await auction.getNextPrice(rats.address, id);
    let ratsCoin = (await auction.getItem(rats.address, id)).native ? "MATIC" : "LFG";
    expect(ratsInitialPrice).to.equal(priceMatic);
    expect(ratsCoin).to.equal("MATIC");

    // bid without value
    await expect(auction.connect(bob).bid(rats.address, id)).to.be.revertedWith("InsufficientFunds()");
    // successful bid
    await expect(auction.connect(bob).bid(rats.address, id, {value: ratsInitialPrice})).to.emit(auction, "Bid");

    expect(await ethers.provider.getBalance(auction.address)).to.equal(ratsInitialPrice);

    // raising price
    let price = await auction.getNextPrice(rats.address, id);
    expect(price).to.equal(ratsInitialPrice.add(ratsInitialPrice.mul(10).div(100)));

    let fee = await auction.getFee(rats.address, id);
    let totalFee = ratsInitialPrice.add(fee);

    // alice bids
    await expect(auction.connect(alice).bid(rats.address, id, {value: price})).to.emit(auction, "Bid");

    expect(await ethers.provider.getBalance(auction.address)).to.equal(totalFee);

    price = await auction.getNextPrice(rats.address, id);
    fee = await auction.getFee(rats.address, id);
    totalFee = totalFee.add(fee);

    let fredBalanceBefore = await ethers.provider.getBalance(fred.address);

    // fred over bids, sending twice the price
    await expect(auction.connect(fred).bid(rats.address, id, {value: price.mul(2)})).to.emit(auction, "Bid");

    let fredBalanceAfter = await ethers.provider.getBalance(fred.address);
    let remaining = fredBalanceBefore.sub(fredBalanceAfter);
    // we account for the gas used
    expect(remaining.div("1000000000000000").toNumber()).to.equal(price.div("1000000000000000").toNumber());

    // an hour passes
    await increaseBlockTimestampBy(3600 * 10);

    price = await auction.getNextPrice(rats.address, id);

    // bob tries to bid again but auction is over
    await expect(auction.connect(bob).bid(rats.address, id, {value: price})).to.be.revertedWith("AuctionIsOver()");

    await expect(auction.connect(alice).claim(rats.address, id)).to.be.revertedWith("NotTheWinner()");

    await expect(auction.connect(fred).claim(rats.address, id))
      .to.emit(rats, "Transfer")
      .withArgs(auction.address, fred.address, id);

    expect(await ethers.provider.getBalance(auction.address)).to.equal(totalFee);
  });
});
