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
  1 passing (451ms)

-----------------------------|----------|----------|----------|----------|----------------|
File                         |  % Stmts | % Branch |  % Funcs |  % Lines |Uncovered Lines |
-----------------------------|----------|----------|----------|----------|----------------|
 nft/                        |        0 |        0 |        0 |        0 |                |
  PFPAsset.sol               |        0 |        0 |        0 |        0 |... 109,110,112 |
  PFPAuction.sol             |        0 |        0 |        0 |        0 |... 158,160,161 |
  TurnUPNFT.sol              |        0 |        0 |        0 |        0 |           9,13 |
 pool/                       |     7.44 |      5.1 |     8.57 |     9.55 |                |
  CorePool.sol               |     7.79 |     4.84 |     12.5 |        8 |... 430,431,434 |
  ICorePool.sol              |      100 |      100 |      100 |      100 |                |
  Rewards.sol                |     8.82 |     7.14 |     7.14 |    15.56 |... 176,180,184 |
  SharesPool.sol             |        0 |        0 |        0 |        0 |... 32,33,37,41 |
 shares/                     |        0 |        0 |        0 |        0 |                |
  TurnupSharesV4.sol         |        0 |        0 |        0 |        0 |... 705,706,707 |
  TurnupSharesV4c.sol        |        0 |        0 |        0 |        0 |... 89,91,94,98 |
 token/                      |     21.7 |    11.18 |       25 |    25.53 |                |
  LFGFactory.sol             |    10.59 |     7.14 |    15.63 |    14.02 |... 425,429,433 |
  LFGToken.sol               |    66.67 |     22.5 |       50 |    61.76 |... 102,106,108 |
 utils/                      |    61.11 |    33.33 |       80 |    54.55 |                |
  IERC4906.sol               |      100 |      100 |      100 |      100 |                |
  ValidatableUpgradeable.sol |    61.11 |    33.33 |       80 |    54.55 |... 67,68,76,77 |
-----------------------------|----------|----------|----------|----------|----------------|
All files                    |     8.04 |     4.68 |    10.91 |     9.28 |                |
-----------------------------|----------|----------|----------|----------|----------------|
```
