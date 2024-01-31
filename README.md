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
  60 passing (14s)
  1 pending

-----------------------------|----------|----------|----------|----------|----------------|
File                         |  % Stmts | % Branch |  % Funcs |  % Lines |Uncovered Lines |
-----------------------------|----------|----------|----------|----------|----------------|
 nft/                        |    65.63 |    41.46 |    58.33 |     62.5 |                |
  PFPAsset.sol               |    44.44 |    15.38 |    36.36 |       40 |... 3,97,98,102 |
  PFPAuction.sol             |    72.73 |     53.7 |    72.73 |     71.7 |... 158,160,161 |
  TurnUPNFT.sol              |      100 |       50 |      100 |      100 |                |
 pool/                       |       80 |    47.87 |    76.47 |    81.21 |                |
  CorePool.sol               |    77.46 |    46.55 |       80 |    77.42 |... 422,423,426 |
  ICorePool.sol              |      100 |      100 |      100 |      100 |                |
  Rewards.sol                |    85.29 |    57.14 |    78.57 |    88.64 |... 140,165,169 |
  SharesPool.sol             |       80 |       25 |       60 |    83.33 |          37,41 |
 shares/                     |    95.13 |    67.34 |    96.49 |    96.06 |                |
  TurnupSharesV4.sol         |    94.85 |     69.2 |    97.87 |    96.25 |... 249,251,665 |
  TurnupSharesV4c.sol        |    96.88 |       50 |       90 |    94.87 |          91,98 |
 token/                      |    81.55 |    41.43 |    66.67 |    81.62 |                |
  LFGFactory.sol             |    79.52 |    44.23 |    64.52 |    80.77 |... 409,413,417 |
  LFGToken.sol               |       90 |    33.33 |    72.73 |    84.38 | 36,37,41,42,70 |
 utils/                      |    83.33 |    38.89 |      100 |    72.73 |                |
  IERC4906.sol               |      100 |      100 |      100 |      100 |                |
  ValidatableUpgradeable.sol |    83.33 |    38.89 |      100 |    72.73 |... 54,56,57,59 |
-----------------------------|----------|----------|----------|----------|----------------|
All files                    |    85.17 |    53.44 |    79.01 |    84.98 |                |
-----------------------------|----------|----------|----------|----------|----------------|

> Istanbul reports written to ./coverage/ and ./coverage.json

```
