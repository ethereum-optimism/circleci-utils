#!/bin/bash

# This script will retrieve the changesets action script from the changesets-action repository

mkdir -p 1.4.9
# We need to clone the repository
curl -L https://raw.githubusercontent.com/changesets/action/refs/tags/v1.4.9/dist/index.js -o 1.4.9/index.js
