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
  45 passing (5s)

-----------------------------|----------|----------|----------|----------|----------------|
File                         |  % Stmts | % Branch |  % Funcs |  % Lines |Uncovered Lines |
-----------------------------|----------|----------|----------|----------|----------------|
 contracts/                  |    87.13 |    49.04 |    64.71 |    82.72 |                |
  TurnupSharesV4.sol         |    98.32 |    70.83 |    97.78 |    99.12 |        183,637 |
  TurnupSharesV4Pausable.sol |        0 |        0 |        0 |        0 |... 67,68,70,71 |
  TurnupSharesV5.sol         |        0 |        0 |        0 |        0 |... 103,104,105 |
-----------------------------|----------|----------|----------|----------|----------------|
All files                    |    87.13 |    49.04 |    64.71 |    82.72 |                |
-----------------------------|----------|----------|----------|----------|----------------|
```
