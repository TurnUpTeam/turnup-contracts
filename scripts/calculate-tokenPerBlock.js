const {expect} = require("chai");
const {ethers} = require("hardhat");

function toBigInt(number) {
  return BigInt(ethers.utils.parseEther(number.toString()).toString());
}

// This is working in theory but in practice it's not working
// Ignore it

const weeksPerYear = 52;
const durationYears = 2; // Duration of the pool in years
const weeklyDecay = 0.97; // 3% decay per week
const blocksPerDayPolygon = 42000; // Average number of blocks per day in Polygon
const blocksPerWeekPolygon = blocksPerDayPolygon * 7; // Blocks per week in Polygon
const totalWeeks = durationYears * weeksPerYear;
const decayFactor = weeklyDecay;

function validateTokenPerBlock(reservedAmount, tokenPerBlock) {
  let totalRewards = 0n;
  let decayFactor = BigInt(weeklyDecay * 100);
  let decayPeriods = weeksPerYear * durationYears;
  for (let i = 0; i < decayPeriods; i++) {
    totalRewards += tokenPerBlock * BigInt(blocksPerWeekPolygon);
    tokenPerBlock = (tokenPerBlock * decayFactor) / 100n;
  }
  return totalRewards < reservedAmount;
}

// Calculate r^n
const decayOverDuration = Math.pow(decayFactor, totalWeeks);
function calculateInitialTokensPerBlock(totalRewards) {
  // Calculate the first term of the geometric series
  const firstTerm = (totalRewards * (1 - decayFactor)) / (1 - decayOverDuration);

  // Calculate the initial tokens per block
  return toBigInt(firstTerm / blocksPerWeekPolygon);
}

// Constants
let totalRewards = 400000000; // Total tokens to be distributed
console.log("Total rewards:", totalRewards);
// Calculate the initial tokens per block
let initialTokens = calculateInitialTokensPerBlock(totalRewards);
console.log("Initial tokens per block:", initialTokens);
console.log(toBigInt(totalRewards / 95e5));
console.log("Validate token per block", validateTokenPerBlock(toBigInt(totalRewards), toBigInt(totalRewards / 95e5)));

totalRewards = 1245000000; // Total tokens to be distributed
console.log("Total rewards:", totalRewards);
let initialTokens2 = calculateInitialTokensPerBlock(totalRewards);
console.log("Initial tokens per block:", initialTokens2);
console.log(toBigInt(totalRewards / 95e5));
console.log("Validate token per block", validateTokenPerBlock(toBigInt(totalRewards), toBigInt(totalRewards / 95e5)));
