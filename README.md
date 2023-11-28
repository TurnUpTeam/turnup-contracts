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
  1 passing (398ms)

----------------------|----------|----------|----------|----------|----------------|
File                  |  % Stmts | % Branch |  % Funcs |  % Lines |Uncovered Lines |
----------------------|----------|----------|----------|----------|----------------|
 contracts/           |    24.43 |    17.91 |    56.67 |       25 |                |
  TurnupSharesV4.sol  |    24.43 |    17.91 |    56.67 |       25 |... 513,515,516 |
 contracts/mocks/     |        0 |        0 |        0 |        0 |                |
  TurnupSharesV3.sol  |        0 |        0 |        0 |        0 |... 122,123,125 |
  TurnupSharesV4b.sol |        0 |      100 |        0 |        0 |             10 |
----------------------|----------|----------|----------|----------|----------------|
All files             |    18.71 |    14.63 |    39.53 |    19.43 |                |
----------------------|----------|----------|----------|----------|----------------|
```
