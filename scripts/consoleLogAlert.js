const {execSync} = require("child_process");
const path = require("path");

function consoleLogAlert() {
  let error = false;
  try {
    const result = execSync(`grep -r 'import "hardhat' ${path.resolve(__dirname, "../contracts")}`).toString();
    if (/:import/.test(result)) {
      error = true;
    }
  } catch (e) {
    // nothing found
  }
  if (error) {
    throw new Error("At least a console.log has been left in the contracts");
  }
}

module.exports = consoleLogAlert;
