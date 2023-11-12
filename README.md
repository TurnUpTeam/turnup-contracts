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

### Check the format and lint

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
  23 passing (2s)

----------------------|----------|----------|----------|----------|----------------|
File                  |  % Stmts | % Branch |  % Funcs |  % Lines |Uncovered Lines |
----------------------|----------|----------|----------|----------|----------------|
 contracts/           |    94.17 |    63.33 |      100 |    93.42 |                |
  TurnupSharesV4.sol  |    94.17 |    63.33 |      100 |    93.42 |... 379,450,451 |
 contracts/mocks/     |      2.5 |        0 |     7.69 |     2.13 |                |
  TurnupSharesV3.sol  |        0 |        0 |        0 |        0 |... 122,123,125 |
  TurnupSharesV4b.sol |      100 |      100 |      100 |      100 |                |
----------------------|----------|----------|----------|----------|----------------|
All files             |    71.25 |    50.67 |    71.43 |    71.86 |                |
----------------------|----------|----------|----------|----------|----------------|
```
