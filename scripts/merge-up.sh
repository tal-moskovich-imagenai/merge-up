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

# Function to find the base branch (master or main)
find_base_branch() {
    if git show-ref --verify --quiet refs/heads/master; then
        echo "master"
    elif git show-ref --verify --quiet refs/heads/main; then
        echo "main"
    else
        echo "Error: Neither master nor main branch found"
        exit 1
    fi
}

# Function to find branches based on master/main
find_branches() {
    local BASE_BRANCH=$(find_base_branch)
    echo "Finding branches based on $BASE_BRANCH..."

    # Create temporary directory for our files
    mkdir -p /tmp/git-merge-up

    # Start with base branch
    echo "$BASE_BRANCH" > /tmp/git-merge-up/branch_order

    # Function to check if a branch is based on another branch
    is_based_on() {
        local branch="$1"
        local base="$2"
        git merge-base --is-ancestor "$base" "$branch" 2>/dev/null
    }

    # Get all commits between current branch and base branch
    git rev-list --ancestry-path --first-parent "$BASE_BRANCH".."$CURRENT_BRANCH" > /tmp/git-merge-up/commits

    # Get all local branches
    git for-each-ref --format='%(refname:short)' refs/heads/ | \
        grep -v "^$CURRENT_BRANCH$" | \
        grep -v "^$BASE_BRANCH$" | \
        grep -v "^main$" | \
        grep -v "^master$" > /tmp/git-merge-up/all_branches

    # Find intermediate branches
    while IFS= read -r branch; do
        # Check if this branch is between current and base
        if is_based_on "$CURRENT_BRANCH" "$branch" && is_based_on "$branch" "$BASE_BRANCH"; then
            # Get the merge-base commit with current branch
            local merge_base=$(git merge-base "$CURRENT_BRANCH" "$branch")
            # Check if this merge-base is in our commit list
            if grep -q "$merge_base" /tmp/git-merge-up/commits; then
                echo "$branch" >> /tmp/git-merge-up/intermediate_branches
            fi
        fi
    done < /tmp/git-merge-up/all_branches

    # Sort intermediate branches by their distance from base (in reverse order)
    if [ -f /tmp/git-merge-up/intermediate_branches ]; then
        cat /tmp/git-merge-up/intermediate_branches | while read branch; do
            echo "$(git rev-list --count "$BASE_BRANCH".."$branch") $branch"
        done | sort -rn | cut -d' ' -f2 >> /tmp/git-merge-up/branch_order
    fi

    # Add current branch at the end
    echo "$CURRENT_BRANCH" >> /tmp/git-merge-up/branch_order

    # Create initial selection file
    cp /tmp/git-merge-up/branch_order /tmp/git-merge-up/selected_branches

    # Clean up temporary files
    rm -f /tmp/git-merge-up/commits /tmp/git-merge-up/all_branches /tmp/git-merge-up/intermediate_branches
}

# Function to display current selection
display_selection() {
    echo -e "\n${GREEN}Current branch selection:${NC}"
    local counter=1
    while IFS= read -r branch; do
        if grep -Fxq "$branch" /tmp/git-merge-up/selected_branches; then
            echo -e "${GREEN}[$counter] ✓ $branch${NC}"
        else
            echo -e "[$counter]   $branch"
        fi
        ((counter++))
    done < /tmp/git-merge-up/branch_order
    echo -e "\n${YELLOW}Commands:${NC}"
    echo "  <number> - Toggle branch"
    echo "  'a'     - Select all"
    echo "  'n'     - Deselect all"
    echo "  'c'     - Confirm and proceed"
    echo "  'q'     - Quit"
}

# Function to toggle a branch
toggle_branch() {
    local branch
    branch=$(sed -n "${1}p" /tmp/git-merge-up/branch_order)
    if grep -Fxq "$branch" /tmp/git-merge-up/selected_branches; then
        # Create a temporary file without the branch
        grep -Fxv "$branch" /tmp/git-merge-up/selected_branches > /tmp/git-merge-up/selected_branches.tmp
        mv /tmp/git-merge-up/selected_branches.tmp /tmp/git-merge-up/selected_branches
    else
        echo "$branch" >> /tmp/git-merge-up/selected_branches
    fi
}

# Function to select all branches
select_all() {
    cp /tmp/git-merge-up/branch_order /tmp/git-merge-up/selected_branches
}

# Function to deselect all branches
deselect_all() {
    rm -f /tmp/git-merge-up/selected_branches
    touch /tmp/git-merge-up/selected_branches
}

# Function to perform merges
perform_merges() {
    local ORIGINAL_BRANCH="$CURRENT_BRANCH"
    local has_errors=false
    local previous_branch=""

    # Read the first selected branch to start with
    previous_branch=$(head -n1 /tmp/git-merge-up/selected_branches)

    while IFS= read -r branch; do
        if [ "$branch" != "$previous_branch" ] && grep -Fxq "$branch" /tmp/git-merge-up/selected_branches; then
            echo -e "${YELLOW}Merging $previous_branch into $branch...${NC}"
            git checkout "$branch"

            # Attempt the merge
            git merge "$previous_branch"

            # Check if merge resulted in conflicts
            if [ $? -ne 0 ]; then
                echo -e "${RED}Merge failed for $branch${NC}"

                # Check git status for conflicts
                if git status | grep -q "both modified:"; then
                    echo -e "${RED}Merge conflicts detected in the following files:${NC}"
                    git status | grep "both modified:"
                    echo -e "\n${YELLOW}Please resolve the conflicts and try again.${NC}"
                    echo -e "${YELLOW}You can use 'git status' to see the conflicting files.${NC}"
                else
                    echo -e "${YELLOW}Merge failed but no conflicts found. Please check git status.${NC}"
                fi

                has_errors=true
                break
            else
                echo -e "${GREEN}Successfully merged $previous_branch into $branch${NC}"
                previous_branch="$branch"
            fi
        fi
    done < /tmp/git-merge-up/branch_order

    # Return to original branch
    git checkout "$ORIGINAL_BRANCH"

    if [ "$has_errors" = false ]; then
        echo -e "${GREEN}All selected merges completed successfully!${NC}"
    fi
}

# Main interactive loop
find_branches

echo -e "${GREEN}Select branches to merge (press 'c' to confirm):${NC}"
while true; do
    display_selection
    read -p "Enter command: " cmd

    case $cmd in
        [0-9]*)
            if [ "$cmd" -ge 1 ] && [ "$cmd" -le "$(wc -l < /tmp/git-merge-up/branch_order)" ]; then
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
            if [ -s /tmp/git-merge-up/selected_branches ]; then
                echo -e "${YELLOW}The following merges will be performed:${NC}"
                local previous_branch=$(head -n1 /tmp/git-merge-up/selected_branches)
                while IFS= read -r branch; do
                    if [ "$branch" != "$previous_branch" ] && grep -Fxq "$branch" /tmp/git-merge-up/selected_branches; then
                        echo -e "${GREEN}$previous_branch -> $branch${NC}"
                        previous_branch=$branch
                    fi
                done < /tmp/git-merge-up/branch_order

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
rm -rf /tmp/git-merge-up
