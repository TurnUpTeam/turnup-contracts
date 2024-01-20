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
  2 passing (605ms)

-----------------------------|----------|----------|----------|----------|----------------|
File                         |  % Stmts | % Branch |  % Funcs |  % Lines |Uncovered Lines |
-----------------------------|----------|----------|----------|----------|----------------|
 erc20Lockable/              |    12.28 |    13.89 |       20 |     9.23 |                |
  ERC20Lockable.sol          |    12.28 |    13.89 |       20 |     9.23 |... 166,168,172 |
  IERC20Lockable.sol         |      100 |      100 |      100 |      100 |                |
 pool/                       |    70.75 |    39.19 |    63.64 |    70.27 |                |
  CorePool.sol               |    74.26 |    39.19 |       70 |    73.76 |... 675,676,679 |
  ICorePool.sol              |      100 |      100 |      100 |      100 |                |
  SharesPool.sol             |        0 |      100 |        0 |        0 |... 22,23,24,25 |
 shares/                     |        0 |        0 |        0 |        0 |                |
  TurnupSharesV4.sol         |        0 |        0 |        0 |        0 |... 705,706,707 |
  TurnupSharesV4c.sol        |        0 |        0 |        0 |        0 |... 89,91,94,98 |
 token/                      |    26.19 |    11.67 |    28.21 |     29.2 |                |
  LFGFactory.sol             |     19.3 |     8.57 |    19.05 |    18.92 |... 250,251,252 |
  LFGToken.sol               |    40.74 |       16 |    38.89 |    48.72 |... 131,132,133 |
 utils/                      |    61.11 |    33.33 |       80 |    54.55 |                |
  ValidatableUpgradeable.sol |    61.11 |    33.33 |       80 |    54.55 |... 67,68,76,77 |
-----------------------------|----------|----------|----------|----------|----------------|
All files                    |    23.42 |    10.89 |    26.17 |    24.72 |                |
-----------------------------|----------|----------|----------|----------|----------------|
```
