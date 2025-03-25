# Merge Up Script

A utility script for performing bottom-to-top branch merging from master into feature branches.

## Usage

The script helps you merge changes from master into feature branches in the correct order, ensuring that dependencies between branches are respected.

### Basic Usage

To see the merge order (without actually performing merges):
```bash
./scripts/merge-up.sh
```

To actually perform the merges:
```bash
./scripts/merge-up.sh --execute
```

### Options

- `--execute`: Actually perform the merges (without this flag, only shows the order)
- `--help` or `-h`: Show help message

## How It Works

1. Finds all branches that are based on master
2. Determines the correct merge order by analyzing merge base dates
3. Shows you the order of branches (bottom to top)
4. If `--execute` is used:
   - Checks out each branch in order
   - Merges master into it
   - Handles any merge conflicts
   - Returns to your original branch when done

## Features

- Color-coded output for better visibility
- Safety checks (ensures you're in a git repository)
- Preserves your current branch position
- Handles merge conflicts gracefully
- Shows clear progress and status messages

## Safety

The script is designed to be safe by default - it will only show the merge order unless you explicitly use the `--execute` flag. This way, you can review the order before actually performing any merges. 