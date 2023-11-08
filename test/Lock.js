const {expect} = require("chai");
// const { ethers } = require('hardhat');

describe("Lock", function () {
  let Lock;
  let lock;
  let owner;
  let addr1;
  let unlockTime;

  beforeEach(async function () {
    // Get the ContractFactory and Signers here.
    Lock = await ethers.getContractFactory("Lock");
    [owner, addr1] = await ethers.getSigners();

    // Set the unlock time to 10 minutes from the current block timestamp
    unlockTime = (await ethers.provider.getBlock("latest")).timestamp + 600;

    // Deploy a new Lock contract with the unlock time set to 10 minutes in the future
    lock = await Lock.deploy(unlockTime, {value: ethers.utils.parseEther("1")});
    await lock.deployed();
  });

  // Test case for successful withdrawal
  it("should withdraw after unlock time", async function () {
    // Increase the EVM time to the unlock time
    await ethers.provider.send("evm_increaseTime", [600]); // 10 minutes
    await ethers.provider.send("evm_mine");

    // Withdraw the funds
    await expect(lock.withdraw())
      .to.emit(lock, "Withdrawal")
      .withArgs(ethers.utils.parseEther("1"), (await ethers.provider.getBlock("latest")).timestamp + 1);

    // Check the contract balance is 0
    expect(await ethers.provider.getBalance(lock.address)).to.equal(0);
  });

  // Test case for withdrawal attempt before unlock time
  it("should fail if trying to withdraw too early", async function () {
    await expect(lock.withdraw()).to.be.revertedWith("You can't withdraw yet");
  });

  // Test case for withdrawal attempt by non-owner
  it("should fail if non-owner tries to withdraw", async function () {
    // Increase the EVM time to the unlock time
    await ethers.provider.send("evm_increaseTime", [600]); // 10 minutes
    await ethers.provider.send("evm_mine");

    // Attempt to withdraw from a different address
    await expect(lock.connect(addr1).withdraw()).to.be.revertedWith("You aren't the owner");
  });

  // Test case for incorrect constructor arguments
  it("should fail if unlock time is in the past", async function () {
    const pastUnlockTime = (await ethers.provider.getBlock("latest")).timestamp - 1;
    await expect(Lock.deploy(pastUnlockTime, {value: ethers.utils.parseEther("1")})).to.be.revertedWith(
      "Unlock time should be in the future"
    );
  });
});
