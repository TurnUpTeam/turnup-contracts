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
  62 passing (26s)

-----------------------------|----------|----------|----------|----------|----------------|
File                         |  % Stmts | % Branch |  % Funcs |  % Lines |Uncovered Lines |
-----------------------------|----------|----------|----------|----------|----------------|
 pool/                       |    92.17 |    57.45 |    85.29 |    93.96 |                |
  CorePool.sol               |    97.18 |    62.07 |      100 |    97.85 |        394,395 |
  ICorePool.sol              |      100 |      100 |      100 |      100 |                |
  Rewards.sol                |    85.29 |    57.14 |    78.57 |    88.64 |... 142,167,171 |
  SharesPool.sol             |       80 |       25 |       60 |    83.33 |          37,41 |
 shares/                     |    95.13 |    67.34 |    96.49 |    96.06 |                |
  TurnupSharesV4.sol         |    94.85 |     69.2 |    97.87 |    96.25 |... 249,251,665 |
  TurnupSharesV4c.sol        |    96.88 |       50 |       90 |    94.87 |          91,98 |
 token/                      |    81.55 |    41.43 |    66.67 |    81.62 |                |
  LFGFactory.sol             |    79.52 |    44.23 |    64.52 |    80.77 |... 409,413,417 |
  LFGToken.sol               |       90 |    33.33 |    72.73 |    84.38 | 36,37,41,42,70 |
 utils/                      |    83.33 |    38.89 |      100 |    72.73 |                |
  ValidatableUpgradeable.sol |    83.33 |    38.89 |      100 |    72.73 |... 54,56,57,59 |
-----------------------------|----------|----------|----------|----------|----------------|
All files                    |    90.91 |     57.2 |    84.78 |     91.3 |                |
-----------------------------|----------|----------|----------|----------|----------------|
```
