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
  88 passing (27s)
  1 pending

-----------------------------|----------|----------|----------|----------|----------------|
File                         |  % Stmts | % Branch |  % Funcs |  % Lines |Uncovered Lines |
-----------------------------|----------|----------|----------|----------|----------------|
 lottery/                    |    28.97 |    23.13 |    46.15 |    28.89 |                |
  Lottery.sol                |    28.97 |    23.13 |    46.15 |    28.89 |... 377,381,385 |
 nft/                        |    65.22 |    39.86 |    65.52 |    60.51 |                |
  PFPAsset.sol               |    44.44 |    15.38 |    36.36 |       40 |... 3,97,98,102 |
  PFPAuction.sol             |    68.42 |       45 |    81.25 |    63.85 |... 381,382,383 |
  TurnUPNFT.sol              |      100 |       50 |      100 |      100 |                |
 pool/                       |    92.56 |    57.14 |    85.71 |    94.27 |                |
  CorePool.sol               |     97.4 |    61.29 |      100 |       98 |        411,412 |
  ICorePool.sol              |      100 |      100 |      100 |      100 |                |
  Rewards.sol                |    85.29 |    57.14 |    78.57 |    88.89 |... 155,180,184 |
  SharesPool.sol             |       80 |       25 |       60 |    83.33 |          37,41 |
 shares/                     |    95.13 |    67.34 |    96.49 |    96.06 |                |
  TurnupSharesV4.sol         |    94.85 |     69.2 |    97.87 |    96.25 |... 249,251,665 |
  TurnupSharesV4c.sol        |    96.88 |       50 |       90 |    94.87 |          91,98 |
 token/                      |    72.06 |    38.78 |    59.32 |    71.11 |                |
  LFGFactory.sol             |       79 |    45.59 |    72.22 |     79.2 |... 481,482,483 |
  LFGToken.sol               |    90.48 |       35 |       75 |    85.29 | 36,37,41,42,70 |
  LFGTokenV2.sol             |        0 |        0 |        0 |        0 |... 70,74,78,82 |
 utils/                      |    83.33 |    38.89 |      100 |    72.73 |                |
  IERC4906.sol               |      100 |      100 |      100 |      100 |                |
  ValidatableUpgradeable.sol |    83.33 |    38.89 |      100 |    72.73 |... 54,56,57,59 |
-----------------------------|----------|----------|----------|----------|----------------|
All files                    |    75.52 |    47.03 |    73.93 |    74.62 |                |
-----------------------------|----------|----------|----------|----------|----------------|

> Istanbul reports written to ./coverage/ and ./coverage.json

```
