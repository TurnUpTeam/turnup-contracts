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
  52 passing (5s)

-----------------------------|----------|----------|----------|----------|----------------|
File                         |  % Stmts | % Branch |  % Funcs |  % Lines |Uncovered Lines |
-----------------------------|----------|----------|----------|----------|----------------|
 erc20Lockable/              |    63.16 |    52.78 |       60 |    61.54 |                |
  ERC20Lockable.sol          |    63.16 |    52.78 |       60 |    61.54 |... 135,139,140 |
  IERC20Lockable.sol         |      100 |      100 |      100 |      100 |                |
 pool/                       |     62.5 |    33.33 |     62.5 |    60.69 |                |
  CorePool.sol               |    60.61 |    33.33 |    58.62 |     58.7 |... 655,656,659 |
  ICorePool.sol              |      100 |      100 |      100 |      100 |                |
  SharesPool.sol             |      100 |      100 |      100 |      100 |                |
 shares/                     |    98.57 |    68.75 |    98.15 |    98.87 |                |
  TurnupSharesV4.sol         |    98.32 |    70.83 |    97.78 |    99.12 |        183,637 |
  TurnupSharesV4c.sol        |      100 |       50 |      100 |    97.37 |             91 |
 token/                      |    82.43 |    35.58 |    72.97 |    79.41 |                |
  LFGFactory.sol             |    74.47 |    33.33 |    57.89 |    69.84 |... 219,220,221 |
  LFGToken.sol               |     96.3 |       38 |    88.89 |    94.87 |         68,103 |
 utils/                      |    83.33 |    38.89 |      100 |    72.73 |                |
  ValidatableUpgradeable.sol |    83.33 |    38.89 |      100 |    72.73 |... 54,56,57,59 |
-----------------------------|----------|----------|----------|----------|----------------|
All files                    |    82.94 |    53.62 |    79.72 |     81.3 |                |
-----------------------------|----------|----------|----------|----------|----------------|
```
