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
  1 passing (638ms)

-----------------------------|----------|----------|----------|----------|----------------|
File                         |  % Stmts | % Branch |  % Funcs |  % Lines |Uncovered Lines |
-----------------------------|----------|----------|----------|----------|----------------|
 nft/                        |        0 |        0 |        0 |        0 |                |
  PFPAsset.sol               |        0 |        0 |        0 |        0 |... 109,110,112 |
  PFPAuction.sol             |        0 |        0 |        0 |        0 |... 158,160,161 |
  TurnUPNFT.sol              |        0 |        0 |        0 |        0 |           9,13 |
 pool/                       |    59.48 |    31.25 |    47.06 |    61.18 |                |
  CorePool.sol               |    57.75 |    27.59 |       40 |    56.99 |... 422,423,426 |
  ICorePool.sol              |      100 |      100 |      100 |      100 |                |
  Rewards.sol                |       80 |    46.67 |    71.43 |    85.11 |... 147,172,176 |
  SharesPool.sol             |        0 |        0 |        0 |        0 |... 32,33,37,41 |
 shares/                     |        0 |        0 |        0 |        0 |                |
  TurnupSharesV4.sol         |        0 |        0 |        0 |        0 |... 705,706,707 |
  TurnupSharesV4c.sol        |        0 |        0 |        0 |        0 |... 89,91,94,98 |
 token/                      |    24.27 |    11.43 |    21.43 |    25.74 |                |
  LFGFactory.sol             |    14.46 |     8.65 |     12.9 |    15.38 |... 409,413,417 |
  LFGToken.sol               |       65 |    19.44 |    45.45 |    59.38 |... 4,95,99,101 |
 utils/                      |    61.11 |    33.33 |       80 |    54.55 |                |
  IERC4906.sol               |      100 |      100 |      100 |      100 |                |
  ValidatableUpgradeable.sol |    61.11 |    33.33 |       80 |    54.55 |... 67,68,76,77 |
-----------------------------|----------|----------|----------|----------|----------------|
All files                    |    19.92 |      8.9 |     17.9 |    20.93 |                |
-----------------------------|----------|----------|----------|----------|----------------|
```
