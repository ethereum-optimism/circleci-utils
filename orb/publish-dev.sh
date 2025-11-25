#!/bin/bash

FILE_PATH=$(dirname $0)
cd $FILE_PATH/src

#check if orb.yml is valid
circleci orb validate @orb.yml

#if not valid, exit
if [ $? -ne 0 ]; then
  exit 1
fi

#pack orb
rm -f orb.yml
circleci orb pack ./ > orb.yml

# Get current branch name and sanitize it for use in orb version
BRANCH_NAME=$(git branch --show-current | sed 's/\//-/g')
circleci orb publish orb.yml ethereum-optimism/circleci-utils@dev:$BRANCH_NAME

