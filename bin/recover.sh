#!/usr/bin/env bash
# must be run from the root

#rm -rf artifacts
#rm -rf cache
#npx hardhat compile

DEBUG=@openzeppelin:upgrades:* CONTRACT=$1 CONTRACT_ADDRESS=$2 CONTRACT_FOLDER=$4 npx hardhat run scripts/recover.js --network $3
