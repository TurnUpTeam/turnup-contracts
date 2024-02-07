const {expect} = require("chai");

const EthDeployUtils = require("eth-deploy-utils");
const deployUtils = new EthDeployUtils();

const {getTimestamp, increaseBlockTimestampBy, cl, addr0} = require("./helpers");
const {ethers} = require("hardhat");

describe("PFPAuction", function () {
  let auction;
  let lfg;
  // three pfp collections
  let owls, rats, pigs;
  const priceLfg = ethers.utils.parseEther("82");
  const priceMatic = ethers.utils.parseEther("130");
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

    auction = await deployUtils.deployProxy("PFPAuction", lfg.address);

    await owls.preMint(auction.address, 20);
    await owls.preMint(auction.address, 20);
    await owls.preMint(auction.address, 20);
    await owls.preMint(auction.address, 20);
    await owls.preMint(auction.address, 20);
    await owls.preMint(owner.address, 20);

    await rats.preMint(auction.address, 20);
    await rats.preMint(auction.address, 20);
    await rats.preMint(auction.address, 10);

    await pigs.preMint(owner.address, 20);
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

  describe("auction simulation", function () {
    it("should allow to bid multiple times over LFG and MATIC paid owls", async function () {
      // owls #1
      let id = 1;
      let startTime = await ts();
      // ten hours
      let endTime = startTime + 60 * 60 * 10;

      await expect(auction.setItemForAuction(owls.address, id, priceLfg, false, startTime, endTime))
        .to.emit(auction, "ItemForAuction")
        .withArgs(owls.address, id, priceLfg, false, startTime, endTime);

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

      // successful bid
      await expect(auction.connect(bob).bid(owls.address, id))
        .to.emit(auction, "Bid")
        .withArgs(owls.address, id, owlsInitialPrice, await ts(), bob.address);

      item = await auction.getItem(owls.address, id);
      expect(item.bidder).to.equal(bob.address);

      // raising price
      let price = await auction.getNextPrice(owls.address, id);
      expect(price).to.equal(owlsInitialPrice.add(owlsInitialPrice.mul(10).div(100)));

      let fee = price.mul(5).div(110);
      let totalFee = owlsInitialPrice.add(fee);

      // alice approves lfg
      await lfg.connect(alice).approve(auction.address, price.mul(10));

      // alice bids
      await expect(auction.connect(alice).bid(owls.address, id))
        .to.emit(auction, "Bid")
        .withArgs(owls.address, id, price, await ts(), alice.address)
        .to.emit(lfg, "Transfer")
        .withArgs(auction.address, bob.address, price.sub(fee));

      // alice bids again
      price = await auction.getNextPrice(owls.address, id);
      fee = price.mul(5).div(110);
      totalFee = totalFee.add(fee);

      await expect(auction.connect(alice).bid(owls.address, id))
        .to.emit(auction, "Bid")
        .withArgs(owls.address, id, price, await ts(), alice.address)
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
        .withArgs(auction.address, alice.address, id);

      expect(await lfg.balanceOf(auction.address)).to.equal(totalFee);

      // owls # 2
      id = 2;
      startTime = await ts();
      endTime = startTime + tenHours;

      await expect(auction.setItemForAuction(owls.address, id, priceMatic, true, startTime, endTime))
        .to.emit(auction, "ItemForAuction")
        .withArgs(owls.address, id, priceMatic, true, startTime, endTime);

      // bob approves LFG and bids
      await expect(lfg.connect(bob).approve(auction.address, owlsInitialPrice))
        .to.emit(lfg, "Approval")
        .withArgs(bob.address, auction.address, owlsInitialPrice);

      now = await ts();

      endTime = await auction.auctionEndTime(owls.address, id);

      await expect(auction.connect(bob).bid(owls.address, id, {value: priceMatic}))
        .to.emit(auction, "Bid")
        .withArgs(owls.address, id, priceMatic, await ts(), bob.address);
      // nobody beats the bid, an hour passes
      await increaseBlockTimestampBy(3600 * 20);

      await expect(auction.connect(bob).claim(owls.address, id))
        .to.emit(owls, "Transfer")
        .withArgs(auction.address, bob.address, id);
    });
  });

  it("should allow to bid multiple times over MATIC paid rats", async function () {
    let id = 1;
    let startTime = await ts();
    let endTime = startTime + 60 * 60 * 10;

    await expect(
      auction.setItemsForAuction(
        [rats.address, owls.address],
        [id, id],
        [priceMatic, priceLfg],
        [true, false],
        [startTime, startTime],
        [endTime, endTime]
      )
    )
      .to.emit(auction, "ItemForAuction")
      .withArgs(rats.address, id, priceMatic, true, startTime, endTime)
      .to.emit(auction, "ItemForAuction")
      .withArgs(owls.address, id, priceLfg, false, startTime, endTime);

    let ratsInitialPrice = await auction.getNextPrice(rats.address, id);
    let ratsCoin = (await auction.getItem(rats.address, id)).native ? "MATIC" : "LFG";
    expect(ratsInitialPrice).to.equal(priceMatic);
    expect(ratsCoin).to.equal("MATIC");

    // bid without value
    await expect(auction.connect(bob).bid(rats.address, id)).to.be.revertedWith("InsufficientFunds()");
    // successful bid
    await expect(auction.connect(bob).bid(rats.address, id, {value: ratsInitialPrice}))
      .to.emit(auction, "Bid")
      .withArgs(rats.address, id, ratsInitialPrice, await ts(), bob.address);

    expect(await ethers.provider.getBalance(auction.address)).to.equal(ratsInitialPrice);

    // raising price
    let price = await auction.getNextPrice(rats.address, id);
    expect(price).to.equal(ratsInitialPrice.add(ratsInitialPrice.mul(10).div(100)));

    let fee = price.mul(5).div(110);
    let totalFee = ratsInitialPrice.add(fee);

    // alice bids
    await expect(auction.connect(alice).bid(rats.address, id, {value: price}))
      .to.emit(auction, "Bid")
      .withArgs(rats.address, id, price, await ts(), alice.address);

    expect(await ethers.provider.getBalance(auction.address)).to.equal(totalFee);

    price = await auction.getNextPrice(rats.address, id);
    fee = price.mul(5).div(110);
    totalFee = totalFee.add(fee);

    let fredBalanceBefore = await ethers.provider.getBalance(fred.address);

    // fred over bids, sending twice the price
    await expect(auction.connect(fred).bid(rats.address, id, {value: price.mul(2)}))
      .to.emit(auction, "Bid")
      .withArgs(rats.address, id, price, await ts(), fred.address);

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
