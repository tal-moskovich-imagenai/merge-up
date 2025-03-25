#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to print usage
print_usage() {
    echo "Usage: $0 [--execute]"
    echo "  --execute: Actually perform the merges (without this flag, only shows the order)"
    echo "  --help: Show this help message"
    exit 1
}

# Parse arguments
EXECUTE=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --execute)
            EXECUTE=true
            shift
            ;;
        --help|-h)
            print_usage
            ;;
        *)
            echo "Unknown option: $1"
            print_usage
            ;;
    esac
done

# Ensure we're in a git repository
if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    echo -e "${RED}Error: Not a git repository${NC}"
    exit 1
fi

# Get current branch
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

# Get all branches that are based on master
echo -e "${YELLOW}Finding branches based on master...${NC}"
BRANCHES=$(git branch --merged master | grep -v "master" | sed 's/^[ *]*//')

if [ -z "$BRANCHES" ]; then
    echo -e "${YELLOW}No branches found that are based on master${NC}"
    exit 0
fi

# Sort branches by their merge order (bottom to top)
echo -e "${YELLOW}Determining merge order...${NC}"
MERGE_ORDER=""
for branch in $BRANCHES; do
    # Get the merge base with master
    MERGE_BASE=$(git merge-base master $branch)
    # Get the commit date of the merge base
    MERGE_DATE=$(git show -s --format=%ct $MERGE_BASE)
    echo "$MERGE_DATE $branch"
done | sort -n | cut -d' ' -f2- > /tmp/branch_order

echo -e "${GREEN}Merge order (bottom to top):${NC}"
cat /tmp/branch_order

if [ "$EXECUTE" = true ]; then
    echo -e "${YELLOW}Starting merge process...${NC}"
    
    # Store the current branch to return to it later
    ORIGINAL_BRANCH=$CURRENT_BRANCH
    
    # Perform merges from bottom to top
    while read -r branch; do
        echo -e "${YELLOW}Merging master into $branch...${NC}"
        git checkout $branch
        if git merge master; then
            echo -e "${GREEN}Successfully merged master into $branch${NC}"
        else
            echo -e "${RED}Merge failed for $branch${NC}"
            echo -e "${YELLOW}Please resolve conflicts and try again${NC}"
            git checkout $ORIGINAL_BRANCH
            exit 1
        fi
    done < /tmp/branch_order
    
    # Return to original branch
    git checkout $ORIGINAL_BRANCH
    echo -e "${GREEN}All merges completed successfully!${NC}"
else
    echo -e "${YELLOW}To execute the merges, run: $0 --execute${NC}"
fi

# Cleanup
rm -f /tmp/branch_order 