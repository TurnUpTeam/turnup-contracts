#!/usr/bin/env bash

EXISTS=

if [[ -f "./.husky/pre-commit" ]]; then
  EXISTS=`cat ./.husky/pre-commit | grep "npx pretty-quick --staged"`
fi

if [[ "$EXISTS" == "" ]]; then
    npx mrm@2 lint-staged
    npx husky-init
    pnpm i -D pretty-quick
    npx husky set .husky/pre-commit "npx pretty-quick --staged && npm run lint && bin/get-coverage.sh && bin/export.sh && git add -A"
fi

