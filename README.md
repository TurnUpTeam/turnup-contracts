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
  121 passing (40s)
  10 pending

-----------------------------|----------|----------|----------|----------|----------------|
File                         |  % Stmts | % Branch |  % Funcs |  % Lines |Uncovered Lines |
-----------------------------|----------|----------|----------|----------|----------------|
 airdrop/                    |      100 |       75 |      100 |      100 |                |
  LFGAirdropV1.sol           |      100 |       75 |      100 |      100 |                |
 lottery/                    |    28.97 |    23.13 |    46.15 |    28.89 |                |
  Lottery.sol                |    28.97 |    23.13 |    46.15 |    28.89 |... 377,381,385 |
 meme/                       |    11.19 |     5.15 |    13.04 |     12.5 |                |
  Meme404.sol                |        0 |        0 |        0 |        0 |... 77,81,85,89 |
  Meme404Factory.sol         |    13.68 |     6.48 |    18.75 |    15.49 |... 465,476,482 |
  Meme404Proxy.sol           |        0 |        0 |        0 |        0 |... 27,28,29,30 |
 nft/                        |    71.43 |       44 |    73.53 |     65.9 |                |
  PFPAsset.sol               |    55.56 |    26.92 |    45.45 |       48 |... 3,97,98,102 |
  PFPAuction.sol             |    73.45 |    47.54 |    85.71 |    68.49 |... 430,431,432 |
  TurnUPNFT.sol              |      100 |       50 |      100 |      100 |                |
 pool/                       |    90.91 |    56.12 |    82.86 |    92.99 |                |
  CorePool.sol               |    94.81 |    59.68 |    93.75 |       96 |411,412,438,439 |
  ICorePool.sol              |      100 |      100 |      100 |      100 |                |
  Rewards.sol                |    85.29 |    57.14 |    78.57 |    88.89 |... 155,180,184 |
  SharesPool.sol             |       80 |       25 |       60 |    83.33 |          37,41 |
 shares/                     |    96.31 |    68.47 |    97.44 |    96.98 |                |
  NFTShares.sol              |      100 |    72.73 |      100 |      100 |                |
  TurnupSharesV4.sol         |    94.85 |     69.2 |    97.87 |    96.25 |... 249,251,665 |
  TurnupSharesV4c.sol        |    96.88 |       50 |       90 |    94.87 |          91,98 |
 token/                      |    90.83 |    48.05 |    78.26 |    88.89 |                |
  LFGFactory.sol             |    90.91 |    52.54 |    79.41 |    90.09 |... 419,450,454 |
  LFGToken.sol               |    90.48 |    33.33 |       75 |    84.85 | 36,37,41,42,70 |
 utils/                      |    83.33 |    38.89 |      100 |    72.73 |                |
  IERC4906.sol               |      100 |      100 |      100 |      100 |                |
  ValidatableUpgradeable.sol |    83.33 |    38.89 |      100 |    72.73 |... 54,56,57,59 |
-----------------------------|----------|----------|----------|----------|----------------|
All files                    |    71.07 |    46.46 |    70.86 |    70.66 |                |
-----------------------------|----------|----------|----------|----------|----------------|

> Istanbul reports written to ./coverage/ and ./coverage.json

```
