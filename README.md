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
  4 passing (3s)
  1 pending

-----------------------------|----------|----------|----------|----------|----------------|
File                         |  % Stmts | % Branch |  % Funcs |  % Lines |Uncovered Lines |
-----------------------------|----------|----------|----------|----------|----------------|
 lottery/                    |        0 |        0 |        0 |        0 |                |
  Lottery.sol                |        0 |        0 |        0 |        0 |... 377,381,385 |
 nft/                        |        0 |        0 |        0 |        0 |                |
  PFPAsset.sol               |        0 |        0 |        0 |        0 |... 109,110,112 |
  PFPAuction.sol             |        0 |        0 |        0 |        0 |... 381,382,383 |
  TurnUPNFT.sol              |        0 |        0 |        0 |        0 |           9,13 |
 pool/                       |    30.83 |    15.63 |    31.43 |    30.97 |                |
  CorePool.sol               |    30.26 |    13.33 |       25 |    29.59 |... 434,438,439 |
  ICorePool.sol              |      100 |      100 |      100 |      100 |                |
  Rewards.sol                |    41.18 |       25 |       50 |    42.22 |... 176,180,184 |
  SharesPool.sol             |        0 |        0 |        0 |        0 |... 32,33,37,41 |
 shares/                     |        0 |        0 |        0 |        0 |                |
  TurnupSharesV4.sol         |        0 |        0 |        0 |        0 |... 705,706,707 |
  TurnupSharesV4c.sol        |        0 |        0 |        0 |        0 |... 89,91,94,98 |
 token/                      |    68.38 |    30.93 |    57.63 |    68.89 |                |
  LFGFactory.sol             |       68 |    34.33 |    55.56 |     69.6 |... 446,450,454 |
  LFGToken.sol               |    71.43 |     22.5 |    58.33 |    67.65 |... 100,101,102 |
  LFGTokenV2.sol             |    66.67 |       25 |    63.64 |    66.67 |... 66,74,78,82 |
 utils/                      |    83.33 |    38.89 |      100 |    72.73 |                |
  IERC4906.sol               |      100 |      100 |      100 |      100 |                |
  ValidatableUpgradeable.sol |    83.33 |    38.89 |      100 |    72.73 |... 54,56,57,59 |
-----------------------------|----------|----------|----------|----------|----------------|
All files                    |    20.08 |     9.79 |     23.7 |    20.26 |                |
-----------------------------|----------|----------|----------|----------|----------------|

> Istanbul reports written to ./coverage/ and ./coverage.json

```
