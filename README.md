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
  54 passing (21s)

-----------------------------|----------|----------|----------|----------|----------------|
File                         |  % Stmts | % Branch |  % Funcs |  % Lines |Uncovered Lines |
-----------------------------|----------|----------|----------|----------|----------------|
 erc20Lockable/              |    63.16 |    52.78 |       60 |    61.54 |                |
  ERC20Lockable.sol          |    63.16 |    52.78 |       60 |    61.54 |... 135,139,140 |
  IERC20Lockable.sol         |      100 |      100 |      100 |      100 |                |
 pool/                       |    77.36 |    40.54 |    75.76 |    76.35 |                |
  CorePool.sol               |    76.24 |    40.54 |    73.33 |    75.18 |... 675,676,679 |
  ICorePool.sol              |      100 |      100 |      100 |      100 |                |
  SharesPool.sol             |      100 |      100 |      100 |      100 |                |
 shares/                     |    95.13 |    67.34 |    96.49 |    96.06 |                |
  TurnupSharesV4.sol         |    94.85 |     69.2 |    97.87 |    96.25 |... 249,251,665 |
  TurnupSharesV4c.sol        |    96.88 |       50 |       90 |    94.87 |          91,98 |
 token/                      |    83.33 |    38.64 |    71.43 |     80.8 |                |
  LFGFactory.sol             |    78.26 |    38.75 |    60.87 |    75.29 |... 301,302,303 |
  LFGToken.sol               |     96.3 |    38.46 |    84.21 |     92.5 |     68,103,118 |
 utils/                      |    83.33 |    38.89 |      100 |    72.73 |                |
  ValidatableUpgradeable.sol |    83.33 |    38.89 |      100 |    72.73 |... 54,56,57,59 |
-----------------------------|----------|----------|----------|----------|----------------|
All files                    |    85.09 |    53.94 |    81.58 |    84.19 |                |
-----------------------------|----------|----------|----------|----------|----------------|
```
