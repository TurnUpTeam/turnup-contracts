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

## Test coverage

```
  25 passing (2s)

---------------------|----------|----------|----------|----------|----------------|
File                 |  % Stmts | % Branch |  % Funcs |  % Lines |Uncovered Lines |
---------------------|----------|----------|----------|----------|----------------|
 contracts/          |    94.59 |    63.39 |      100 |    93.75 |                |
  Lock.sol           |      100 |      100 |      100 |      100 |                |
  TurnupSharesV4.sol |    94.34 |    61.32 |      100 |    93.43 |... 323,395,396 |
---------------------|----------|----------|----------|----------|----------------|
All files            |    94.59 |    63.39 |      100 |    93.75 |                |
---------------------|----------|----------|----------|----------|----------------|
```
