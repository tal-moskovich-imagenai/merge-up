#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to print usage
print_usage() {
    echo "Usage: $0 [--help]"
    echo "  --help: Show this help message"
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
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

# Create ordered list of branches (master should be first, followed by feature branches)
{
    echo "master"
    git branch | grep "feature/" | sed 's/^[ *]*//' | sort
} > /tmp/branch_order

if [ $(wc -l < /tmp/branch_order) -le 1 ]; then
    echo -e "${YELLOW}No feature branches found${NC}"
    exit 0
fi

# Initialize selection file
cp /tmp/branch_order /tmp/selected_branches

# Function to display current selection
display_selection() {
    echo -e "\n${GREEN}Current branch selection:${NC}"
    local counter=1
    while read -r branch; do
        if grep -q "^$branch$" /tmp/selected_branches; then
            echo -e "${GREEN}[$counter] ✓ $branch${NC}"
        else
            echo -e "[$counter]   $branch"
        fi
        ((counter++))
    done < /tmp/branch_order
    echo -e "\n${YELLOW}Commands:${NC}"
    echo "  <number> - Toggle branch"
    echo "  'a'     - Select all"
    echo "  'n'     - Deselect all"
    echo "  'c'     - Confirm and proceed"
    echo "  'q'     - Quit"
}

# Function to toggle a branch
toggle_branch() {
    local branch=$(sed -n "${1}p" /tmp/branch_order)
    if grep -q "^$branch$" /tmp/selected_branches; then
        # Create a temporary file without the branch
        grep -v "^$branch$" /tmp/selected_branches > /tmp/selected_branches.tmp
        mv /tmp/selected_branches.tmp /tmp/selected_branches
    else
        echo "$branch" >> /tmp/selected_branches
    fi
}

# Function to select all branches
select_all() {
    cp /tmp/branch_order /tmp/selected_branches
}

# Function to deselect all branches
deselect_all() {
    rm -f /tmp/selected_branches
    touch /tmp/selected_branches
}

# Function to perform merges
perform_merges() {
    local ORIGINAL_BRANCH=$CURRENT_BRANCH
    local has_errors=false
    local previous_branch="master"

    while read -r branch; do
        if [ "$branch" != "master" ] && grep -q "^$branch$" /tmp/selected_branches; then
            echo -e "${YELLOW}Merging $previous_branch into $branch...${NC}"
            git checkout $branch
            if git merge $previous_branch; then
                echo -e "${GREEN}Successfully merged $previous_branch into $branch${NC}"
                previous_branch=$branch
            else
                echo -e "${RED}Merge failed for $branch${NC}"
                echo -e "${YELLOW}Please resolve conflicts and try again${NC}"
                has_errors=true
                break
            fi
        fi
    done < /tmp/branch_order

    # Return to original branch
    git checkout $ORIGINAL_BRANCH

    if [ "$has_errors" = false ]; then
        echo -e "${GREEN}All selected merges completed successfully!${NC}"
    fi
}

# Main interactive loop
echo -e "${GREEN}Select branches to merge (press 'c' to confirm):${NC}"
while true; do
    display_selection
    read -p "Enter command: " cmd

    case $cmd in
        [0-9]*)
            if [ "$cmd" -ge 1 ] && [ "$cmd" -le "$(wc -l < /tmp/branch_order)" ]; then
                toggle_branch "$cmd"
            else
                echo -e "${RED}Invalid branch number${NC}"
            fi
            ;;
        a)
            select_all
            ;;
        n)
            deselect_all
            ;;
        c)
            # Check if any branches are selected
            if [ -s /tmp/selected_branches ]; then
                echo -e "${YELLOW}The following merges will be performed:${NC}"
                local previous_branch="master"
                while read -r branch; do
                    if [ "$branch" != "master" ] && grep -q "^$branch$" /tmp/selected_branches; then
                        echo -e "${GREEN}$previous_branch -> $branch${NC}"
                        previous_branch=$branch
                    fi
                done < /tmp/branch_order
                
                echo -e "\n${YELLOW}Proceed with these merges? (y/n)${NC}"
                read -p "Enter choice: " confirm
                if [ "$confirm" = "y" ]; then
                    perform_merges
                    break
                else
                    echo -e "${YELLOW}Operation cancelled${NC}"
                    break
                fi
            else
                echo -e "${RED}No branches selected. Please select at least one branch.${NC}"
            fi
            ;;
        q)
            echo -e "${YELLOW}Operation cancelled${NC}"
            break
            ;;
        *)
            echo -e "${RED}Invalid command${NC}"
            ;;
    esac
done

# Cleanup
rm -f /tmp/branch_order /tmp/selected_branches /tmp/selected_branches.tmp 