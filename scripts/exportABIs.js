const fs = require("fs-extra");
const path = require("path");

async function main() {
  const ABIs = {
    when: new Date().toISOString(),
    contracts: {},
  };

  function abi(name, folder, rename) {
    let source = path.resolve(__dirname, `../artifacts/${folder ? folder + "/" : ""}${name}.sol/${name}.json`);
    let json = require(source);
    ABIs.contracts[rename || name] = json.abi;
  }
  abi("TurnupSharesV2", "contracts");
  abi("TurnupSharesV3", "contracts");

  await fs.writeFile(path.resolve(__dirname, "../export/ABIs.json"), JSON.stringify(ABIs, null, 2));
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
