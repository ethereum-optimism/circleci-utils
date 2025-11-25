#!/bin/bash

# Check for dry-run flag
DRY_RUN=false
if [ "$1" == "--dry-run" ] || [ "$1" == "-n" ]; then
    DRY_RUN=true
    echo "========================================="
    echo "DRY RUN MODE - No changes will be made"
    echo "========================================="
    echo ""
fi

FILE_PATH=$(dirname $0)
cd $FILE_PATH/src

#check if orb.yml is valid
echo "Validating orb.yml..."
circleci orb validate @orb.yml

#if not valid, exit
if [ $? -ne 0 ]; then
  echo "Validation failed. Exiting."
  exit 1
fi

if [ "$DRY_RUN" = true ]; then
    echo "✓ Orb validation passed"
    echo ""
fi

# Prompt for the dev version to promote
echo "Available dev versions can be listed with: circleci orb list ethereum-optimism/circleci-utils"
echo ""
read -p "Enter the dev version label to promote (e.g., main, feature-name): " DEV_VERSION

if [ -z "$DEV_VERSION" ]; then
    echo "Error: No dev version specified"
    exit 1
fi

echo ""
echo "Fetching orb versions for comparison..."
echo ""

# Get the current production version
PROD_VERSION=$(circleci orb info ethereum-optimism/circleci-utils 2>/dev/null | grep -i latest | awk '{print $2}' | cut -d'@' -f2)

if [ -z "$PROD_VERSION" ]; then
    echo "Warning: Could not fetch current production version"
    echo ""
else
    echo "Current production version: ethereum-optimism/circleci-utils@$PROD_VERSION"
    echo "Dev version to promote: ethereum-optimism/circleci-utils@dev:$DEV_VERSION"
    echo ""
    
    # Create temporary directory for comparison
    TEMP_DIR=$(mktemp -d)
    trap "rm -rf $TEMP_DIR" EXIT
    
    # Fetch production version
    echo "Downloading production orb..."
    circleci orb source ethereum-optimism/circleci-utils@$PROD_VERSION > "$TEMP_DIR/prod.yml" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        # Fetch dev version
        echo "Downloading dev orb..."
        circleci orb source ethereum-optimism/circleci-utils@dev:$DEV_VERSION > "$TEMP_DIR/dev.yml" 2>/dev/null
        
        if [ $? -eq 0 ]; then
            echo ""
            echo "========================================="
            echo "DIFF: Production vs Dev Version"
            echo "========================================="
            echo ""
            echo "Legend: '-' = removed from production, '+' = added in dev"
            echo ""
            
            # Show the diff
            if command -v colordiff > /dev/null 2>&1; then
                diff -u "$TEMP_DIR/prod.yml" "$TEMP_DIR/dev.yml" | colordiff | tail -n +3
            else
                diff -u "$TEMP_DIR/prod.yml" "$TEMP_DIR/dev.yml" | tail -n +3
            fi
            
            DIFF_EXIT=$?
            echo ""
            
            if [ $DIFF_EXIT -eq 0 ]; then
                echo "❌ Error: No differences found between production and dev version"
                echo ""
                echo "The dev version dev:$DEV_VERSION is identical to production $PROD_VERSION"
                echo "There is nothing to promote. Exiting."
                echo ""
                exit 0
            fi
        else
            echo "Warning: Could not fetch dev version dev:$DEV_VERSION"
            echo "Make sure this dev version exists."
            echo ""
        fi
    else
        echo "Warning: Could not fetch production version"
        echo ""
    fi
fi

#before continuing make sure we ask for confirmation
if [ "$DRY_RUN" = true ]; then
    read -p "Continue with dry run simulation? (y/n) " -n 1 -r
else
    read -p "Are you sure you want to promote dev:$DEV_VERSION to production? (y/n) " -n 1 -r
fi
echo   # (optional) move to a new line
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    exit 1
fi

if [ "$DRY_RUN" = true ]; then
    echo ""
    echo "========================================="
    echo "SIMULATING PROMOTION"
    echo "========================================="
    echo ""
    echo "Would execute:"
    echo "  circleci orb publish promote ethereum-optimism/circleci-utils@dev:$DEV_VERSION patch"
    echo ""
    
    # Get current version to show what would happen
    CURRENT_VERSION=$(circleci orb info ethereum-optimism/circleci-utils 2>/dev/null | grep -i latest | cut -d"@" -f2)
    if [ -n "$CURRENT_VERSION" ]; then
        echo "Current production version: $CURRENT_VERSION"
        echo "Would increment to next patch version"
        echo ""
    fi
    
    echo "✓ Would validate dev version exists"
    echo "✓ Would promote to production (patch increment)"
    echo "✓ Would update latest production version"
else
    circleci orb publish promote ethereum-optimism/circleci-utils@dev:$DEV_VERSION patch

    if [ $? -ne 0 ]; then
        echo "Error: Failed to promote orb"
        exit 1
    fi
fi

echo ""
echo "Successfully $([ "$DRY_RUN" = true ] && echo "simulated promotion" || echo "promoted orb") to production"
echo ""

# Ask if user wants to tag the repository (default yes)
if [ "$DRY_RUN" = true ]; then
    read -p "Would you want to tag the repository with the orb version? (Y/n) " -n 1 -r
else
    read -p "Do you want to tag the repository with the orb version? (Y/n) " -n 1 -r
fi
echo   # move to a new line

# Default to yes if empty or Y/y
if [[ -z $REPLY || $REPLY =~ ^[Yy]$ ]]; then
    if [ "$DRY_RUN" = true ]; then
        echo ""
        echo "========================================="
        echo "SIMULATING REPOSITORY TAGGING"
        echo "========================================="
        echo ""
        
        # Check if we're on main branch
        CURRENT_BRANCH=$(git branch --show-current)
        
        if [ "$CURRENT_BRANCH" != "main" ]; then
            echo "⚠ Warning: Repository tagging can only be done from the main branch"
            echo "  Current branch: $CURRENT_BRANCH"
            echo "  You would need to switch to main branch first"
        else
            echo "✓ On main branch - tagging would be allowed"
            echo ""
            echo "Would execute:"
            echo "  git tag -a orb/<next-version> -m \"Version orb/<next-version>\""
            echo "  git push origin orb/<next-version>"
            echo ""
            echo "Note: <next-version> would be the actual new version after promotion"
        fi
    else
        # Get the directory of this script to call the tagging script
        SCRIPT_DIR=$(dirname $0)
        $SCRIPT_DIR/publish-prod-repository-tag.sh
    fi
else
    echo "$([ "$DRY_RUN" = true ] && echo "Would skip" || echo "Skipping") repository tagging"
fi

if [ "$DRY_RUN" = true ]; then
    echo ""
    echo "========================================="
    echo "DRY RUN COMPLETE"
    echo "========================================="
    echo ""
    echo "No changes were made. To perform the actual promotion, run:"
    echo "  ./publish-prod.sh"
    echo ""
fi