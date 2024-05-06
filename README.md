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
  3 passing (2s)
  8 pending

-----------------------------|----------|----------|----------|----------|----------------|
File                         |  % Stmts | % Branch |  % Funcs |  % Lines |Uncovered Lines |
-----------------------------|----------|----------|----------|----------|----------------|
 airdrop/                    |        0 |        0 |        0 |        0 |                |
  LFGAirdropV1.sol           |        0 |        0 |        0 |        0 |... 87,88,89,91 |
 lottery/                    |        0 |        0 |        0 |        0 |                |
  Lottery.sol                |        0 |        0 |        0 |        0 |... 377,381,385 |
 meme/                       |    11.19 |     5.15 |    13.04 |     12.5 |                |
  Meme404.sol                |        0 |        0 |        0 |        0 |... 77,81,85,89 |
  Meme404Factory.sol         |    13.68 |     6.48 |    18.75 |    15.49 |... 465,476,482 |
  Meme404Proxy.sol           |        0 |        0 |        0 |        0 |... 27,28,29,30 |
 nft/                        |        0 |        0 |        0 |        0 |                |
  PFPAsset.sol               |        0 |        0 |        0 |        0 |... 109,110,112 |
  PFPAuction.sol             |        0 |        0 |        0 |        0 |... 430,431,432 |
  TurnUPNFT.sol              |        0 |        0 |        0 |        0 |           9,13 |
 pool/                       |        0 |        0 |        0 |        0 |                |
  CorePool.sol               |        0 |        0 |        0 |        0 |... 434,438,439 |
  ICorePool.sol              |      100 |      100 |      100 |      100 |                |
  Rewards.sol                |        0 |        0 |        0 |        0 |... 176,180,184 |
  SharesPool.sol             |        0 |        0 |        0 |        0 |... 32,33,37,41 |
 shares/                     |        0 |        0 |        0 |        0 |                |
  NFTShares.sol              |        0 |        0 |        0 |        0 |... 267,268,269 |
  TurnupSharesV4.sol         |        0 |        0 |        0 |        0 |... 705,706,707 |
  TurnupSharesV4c.sol        |        0 |        0 |        0 |        0 |... 89,91,94,98 |
 token/                      |     6.42 |     0.65 |     6.52 |     7.64 |                |
  LFGFactory.sol             |        0 |        0 |        0 |        0 |... 446,450,454 |
  LFGToken.sol               |    33.33 |     2.78 |       25 |    33.33 |... ,99,102,106 |
 utils/                      |    61.11 |    33.33 |       80 |    54.55 |                |
  IERC4906.sol               |      100 |      100 |      100 |      100 |                |
  ValidatableUpgradeable.sol |    61.11 |    33.33 |       80 |    54.55 |... 67,68,76,77 |
-----------------------------|----------|----------|----------|----------|----------------|
All files                    |     3.56 |     1.34 |     4.68 |     3.74 |                |
-----------------------------|----------|----------|----------|----------|----------------|

> Istanbul reports written to ./coverage/ and ./coverage.json

```
