#/bin/bash

FILE_PATH=$(dirname $0)
cd $FILE_PATH/src

#check if orb.yml is valid
circleci orb validate @orb.yml

#if not valid, exit
if [ $? -ne 0 ]; then
  exit 1
fi

# Prompt for the dev version to promote
echo "Available dev versions can be listed with: circleci orb list ethereum-optimism/circleci-utils"
echo ""
read -p "Enter the dev version label to promote (e.g., main, feature-name): " DEV_VERSION

if [ -z "$DEV_VERSION" ]; then
    echo "Error: No dev version specified"
    exit 1
fi

#before continuing make sure we ask for confirmation
read -p "Are you sure you want to promote dev:$DEV_VERSION to production? (y/n) " -n 1 -r
echo   # (optional) move to a new line
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    exit 1
fi

circleci orb publish promote ethereum-optimism/circleci-utils@dev:$DEV_VERSION patch

if [ $? -ne 0 ]; then
    echo "Error: Failed to promote orb"
    exit 1
fi

echo "Successfully promoted orb to production"
echo ""

# Ask if user wants to tag the repository (default yes)
read -p "Do you want to tag the repository with the orb version? (Y/n) " -n 1 -r
echo   # move to a new line

# Default to yes if empty or Y/y
if [[ -z $REPLY || $REPLY =~ ^[Yy]$ ]]; then
    # Get the directory of this script to call the tagging script
    SCRIPT_DIR=$(dirname $0)
    $SCRIPT_DIR/publish-prod-repository-tag.sh
else
    echo "Skipping repository tagging"
fi