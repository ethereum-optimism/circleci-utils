#!/bin/bash

# Check if we're on the main branch
CURRENT_BRANCH=$(git branch --show-current)

if [ "$CURRENT_BRANCH" != "main" ]; then
    echo "Error: Repository tagging can only be done from the main branch"
    echo "Current branch: $CURRENT_BRANCH"
    exit 1
fi

# Get the version of the orb
ORB_VERSION=$(circleci orb info ethereum-optimism/circleci-utils | grep -i latest | cut -d"@" -f2)

if [ -z "$ORB_VERSION" ]; then
    echo "Error: Could not retrieve orb version"
    exit 1
fi

echo "Tagging repository with version: orb/$ORB_VERSION"

# Tag the repository with the version of the orb
git tag -a orb/$ORB_VERSION -m "Version orb/$ORB_VERSION"
git push origin orb/$ORB_VERSION

if [ $? -eq 0 ]; then
    echo "Successfully tagged repository with orb/$ORB_VERSION"
else
    echo "Error: Failed to push tag"
    exit 1
fi

