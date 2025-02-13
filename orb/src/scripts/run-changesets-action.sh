#!/bin/bash

# The CHANGESETS_ACTION_SCRIPT is populated in the CircleCI command from a file
if [ -z "$CHANGESETS_ACTION_SCRIPT" ]; then
    echo "Missing changesets action script. Please make sure to export it as CHANGESETS_ACTION_SCRIPT env variable" >&2
    exit 1
fi

# Also make sure we have node installed
if ! [ -x "$(command -v node)" ]; then
  echo 'Missing node binary' >&2
  exit 1
fi

# Now pipe the script to node
echo $CHANGESETS_ACTION_SCRIPT | node 