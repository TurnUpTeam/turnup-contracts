#!/usr/bin/env bash
# must be run from the root

if [[ "$SKIP_COMPILE" == "" ]]; then
  npm run clean
  NODE_ENV=test npx hardhat compile
fi

node scripts/exportABIs.js
