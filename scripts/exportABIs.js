const fs = require("fs-extra");
const path = require("path");

async function main() {
  const ABIs = {
    contracts: {},
  };

  function abi(name, folder, rename) {
    let source = path.resolve(__dirname, `../artifacts/${folder ? folder + "/" : ""}${name}.sol/${name}.json`);
    let json = require(source);
    ABIs.contracts[rename || name] = json.abi;
  }
  abi("TurnupSharesV4", "contracts/shares");
  abi("TurnupSharesV4c", "contracts/shares");
  abi("CorePool", "contracts/pool");
  abi("SharesPool", "contracts/pool");
  abi("LFGToken", "contracts/token");
  abi("LFGFactory", "contracts/token");

  await fs.writeFile(path.resolve(__dirname, "../export/ABIs.json"), JSON.stringify(ABIs, null, 2));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
