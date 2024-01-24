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
  6 passing (1s)

-----------------------------|----------|----------|----------|----------|----------------|
File                         |  % Stmts | % Branch |  % Funcs |  % Lines |Uncovered Lines |
-----------------------------|----------|----------|----------|----------|----------------|
 erc20Lockable/              |    63.16 |    52.78 |       60 |    61.54 |                |
  ERC20Lockable.sol          |    63.16 |    52.78 |       60 |    61.54 |... 135,139,140 |
  IERC20Lockable.sol         |      100 |      100 |      100 |      100 |                |
 pool/                       |    68.87 |    39.19 |    54.55 |    67.57 |                |
  CorePool.sol               |    72.28 |    39.19 |       60 |    70.92 |... 675,676,679 |
  ICorePool.sol              |      100 |      100 |      100 |      100 |                |
  SharesPool.sol             |        0 |      100 |        0 |        0 |... 22,23,24,25 |
 shares/                     |        0 |        0 |        0 |        0 |                |
  TurnupSharesV4.sol         |        0 |        0 |        0 |        0 |... 705,706,707 |
  TurnupSharesV4c.sol        |        0 |        0 |        0 |        0 |... 89,91,94,98 |
 token/                      |       80 |    35.38 |     67.5 |    76.42 |                |
  LFGFactory.sol             |    79.41 |    38.75 |    63.64 |    76.19 |... 297,298,299 |
  LFGToken.sol               |    81.48 |       30 |    72.22 |    76.92 |... 131,132,133 |
 utils/                      |    83.33 |    38.89 |      100 |    72.73 |                |
  ValidatableUpgradeable.sol |    83.33 |    38.89 |      100 |    72.73 |... 54,56,57,59 |
-----------------------------|----------|----------|----------|----------|----------------|
All files                    |    39.84 |    19.96 |    39.33 |    39.25 |                |
-----------------------------|----------|----------|----------|----------|----------------|
```
