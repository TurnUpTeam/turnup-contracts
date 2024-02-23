# TurnUp Contracts

## Usage

### Clone the repo

```bash
git clone git@github.com:TurnUpTeam/turnup-contracts.git
```

### Install the dependencies

```
npm install
```

### Compile the smart contracts

```
npm run compile
```

### Run the tests

```
npm run test
```

### Run the tests and calculate gas usage

```
npm run test:gas
```

### Run the tests with coverage

```
npm run coverage
```

After running the coverage, you can check it opening the file `coverage/index.html` in your browser.

### Check the lint

```
npm run lint
```

### Get the size of the smart contracts

```
npm run size
```

### Flatten the smart contracts

After deploying to the blockchain, you can flatten the smart contracts to verify the source code on Etherscan with the following command:

```
bin/flatten.sh TurnupSharesV4
```

### To export the ABI

```
bin/export.sh
```

Notice that the ABI is exported anyway during the pre-commit hook.

## Test coverage

```
  1 passing (604ms)

-----------------------------|----------|----------|----------|----------|----------------|
File                         |  % Stmts | % Branch |  % Funcs |  % Lines |Uncovered Lines |
-----------------------------|----------|----------|----------|----------|----------------|
 lottery/                    |        0 |        0 |        0 |        0 |                |
  Lottery.sol                |        0 |        0 |        0 |        0 |... 377,381,385 |
 nft/                        |        0 |        0 |        0 |        0 |                |
  PFPAsset.sol               |        0 |        0 |        0 |        0 |... 109,110,112 |
  PFPAuction.sol             |        0 |        0 |        0 |        0 |... 381,382,383 |
  TurnUPNFT.sol              |        0 |        0 |        0 |        0 |           9,13 |
 pool/                       |     5.83 |     4.17 |     5.71 |     8.39 |                |
  CorePool.sol               |     5.26 |     3.33 |     6.25 |     6.12 |... 434,438,439 |
  ICorePool.sol              |      100 |      100 |      100 |      100 |                |
  Rewards.sol                |     8.82 |     7.14 |     7.14 |    15.56 |... 176,180,184 |
  SharesPool.sol             |        0 |        0 |        0 |        0 |... 32,33,37,41 |
 shares/                     |        0 |        0 |        0 |        0 |                |
  TurnupSharesV4.sol         |        0 |        0 |        0 |        0 |... 705,706,707 |
  TurnupSharesV4c.sol        |        0 |        0 |        0 |        0 |... 89,91,94,98 |
 token/                      |       50 |    25.26 |    49.15 |    52.22 |                |
  LFGFactory.sol             |       44 |    25.37 |    44.44 |     46.4 |... 481,482,483 |
  LFGToken.sol               |    71.43 |     22.5 |    58.33 |    67.65 |... 100,101,102 |
  LFGTokenV2.sol             |       60 |       30 |    54.55 |     61.9 |... 64,66,74,78 |
 utils/                      |    83.33 |    38.89 |      100 |    72.73 |                |
  IERC4906.sol               |      100 |      100 |      100 |      100 |                |
  ValidatableUpgradeable.sol |    83.33 |    38.89 |      100 |    72.73 |... 54,56,57,59 |
-----------------------------|----------|----------|----------|----------|----------------|
All files                    |    12.47 |     7.16 |    17.06 |    13.25 |                |
-----------------------------|----------|----------|----------|----------|----------------|
```
