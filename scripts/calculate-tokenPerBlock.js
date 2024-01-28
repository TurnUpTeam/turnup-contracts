// const {expect} = require("chai");
// const {ethers} = require("hardhat");
//
//   let tokenPerBlock;
//
//   const blocksPerDay = 42000n;
//   const blocksPerWeek = blocksPerDay * 7n;
//   const twoYearsBlocks = blocksPerDay * 365n * 2n;
//   const amountReservedToPool = BigInt(ethers.utils.parseEther("400000000").toString());
//   const decayPeriods = 104n;
//   const decayFactor = 97n;
//
//   function validateInitialAmountPerBlock(reservedAmount, amount) {
//     let totalRewards = 0n;
//     for (let i = 0; i < decayPeriods; i++) {
//       totalRewards += amount * blocksPerWeek;
//       amount = amount * decayFactor / 100n;
//     }
//     // console.log(reservedAmount - totalRewards);
//     return totalRewards < reservedAmount;
//   }
//
// async function main() {
//   let good = true;
//   let factor = 100n;
//   // factor = 326n;
//   let prevFactor = 0n;
//   let prevTokenPerBlock = 0n;
//   let tokenPerBlock = 0n;
//   while (good) {
//     prevFactor = factor;
//     prevTokenPerBlock = tokenPerBlock;
//     factor++;
//     tokenPerBlock = (amountReservedToPool * factor) / (BigInt(twoYearsBlocks) * 100n);
//     good = validateInitialAmountPerBlock(
//         amountReservedToPool,
//         tokenPerBlock
//     );
//   }
//   console.log("tokenPerBlock", prevTokenPerBlock);
//   console.log("factor", prevFactor);
// }
//
// main()
//   .then(() => process.exit(0))
//   .catch((error) => {
//     console.error(error);
//     process.exit(1);
//   });
//

function calculateInitialTokensPerBlock(totalRewards, durationYears, weeklyDecay, blocksPerWeek) {
  const weeksPerYear = 52;
  const totalWeeks = durationYears * weeksPerYear;
  const decayFactor = weeklyDecay;

  // Calculate r^n
  const decayOverDuration = Math.pow(decayFactor, totalWeeks);

  // Calculate the first term of the geometric series
  const firstTerm = (totalRewards * (1 - decayFactor)) / (1 - decayOverDuration);

  // Calculate the initial tokens per block
  const initialTokensPerBlock = firstTerm / blocksPerWeek;
  return initialTokensPerBlock;
}

// Constants
let totalRewards = 400000000; // Total tokens to be distributed
let durationYears = 2; // Duration of the pool in years
let weeklyDecay = 0.97; // 3% decay per week
let blocksPerDayPolygon = 42000; // Average number of blocks per day in Polygon
let blocksPerWeekPolygon = blocksPerDayPolygon * 7; // Blocks per week in Polygon

// Calculate the initial tokens per block
let initialTokens = calculateInitialTokensPerBlock(totalRewards, durationYears, weeklyDecay, blocksPerWeekPolygon);
console.log("Initial tokens per block:", initialTokens);
console.log(totalRewards / 95e5);
totalRewards = 1245000000; // Total tokens to be distributed

let initialTokens2 = calculateInitialTokensPerBlock(totalRewards, durationYears, weeklyDecay, blocksPerWeekPolygon);
console.log("Initial tokens per block:", initialTokens2);
console.log(totalRewards / 95e5);
