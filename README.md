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
  103 passing (27s)
  2 pending

-----------------------------|----------|----------|----------|----------|----------------|
File                         |  % Stmts | % Branch |  % Funcs |  % Lines |Uncovered Lines |
-----------------------------|----------|----------|----------|----------|----------------|
 airdrop/                    |      100 |       75 |      100 |      100 |                |
  LFGAirdropV1.sol           |      100 |       75 |      100 |      100 |                |
 lottery/                    |    28.97 |    23.13 |    46.15 |    28.89 |                |
  Lottery.sol                |    28.97 |    23.13 |    46.15 |    28.89 |... 377,381,385 |
 nft/                        |    66.67 |    40.38 |    65.52 |    59.52 |                |
  PFPAsset.sol               |    44.44 |    15.38 |    36.36 |       40 |... 3,97,98,102 |
  PFPAuction.sol             |    69.81 |    45.31 |    81.25 |    62.41 |... 402,403,404 |
  TurnUPNFT.sol              |      100 |       50 |      100 |      100 |                |
 pool/                       |    90.91 |    56.12 |    82.86 |    92.99 |                |
  CorePool.sol               |    94.81 |    59.68 |    93.75 |       96 |411,412,438,439 |
  ICorePool.sol              |      100 |      100 |      100 |      100 |                |
  Rewards.sol                |    85.29 |    57.14 |    78.57 |    88.89 |... 155,180,184 |
  SharesPool.sol             |       80 |       25 |       60 |    83.33 |          37,41 |
 shares/                     |    95.13 |    67.34 |    96.49 |    96.06 |                |
  TurnupSharesV4.sol         |    94.85 |     69.2 |    97.87 |    96.25 |... 249,251,665 |
  TurnupSharesV4c.sol        |    96.88 |       50 |       90 |    94.87 |          91,98 |
 token/                      |    89.91 |    46.84 |    76.09 |    87.59 |                |
  LFGFactory.sol             |    90.91 |    52.54 |    79.41 |    90.09 |... 419,450,454 |
  LFGToken.sol               |    85.71 |       30 |    66.67 |    79.41 |... 42,70,94,95 |
 utils/                      |    83.33 |    38.89 |      100 |    72.73 |                |
  IERC4906.sol               |      100 |      100 |      100 |      100 |                |
  ValidatableUpgradeable.sol |    83.33 |    38.89 |      100 |    72.73 |... 54,56,57,59 |
-----------------------------|----------|----------|----------|----------|----------------|
All files                    |    78.96 |    50.12 |    79.13 |    77.61 |                |
-----------------------------|----------|----------|----------|----------|----------------|

> Istanbul reports written to ./coverage/ and ./coverage.json

```
