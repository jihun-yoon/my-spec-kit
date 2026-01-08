# GitButler CLI Quick Reference

Quick reference for `but` CLI commands used in the parallel Claude workflow.

## Installation

```bash
# macOS
brew install gitbutlerapp/tap/but

# Verify installation
but --version
```

## Initialize Project

```bash
# Initialize GitButler in an existing git repository
but init
```

## Branch Management

### Show Current Status

```bash
# Show workspace state (branches, changes, marks)
but status

# JSON output (for scripting)
but status --json
```

### Create Branches

```bash
# Create parallel branch (anchors to main/target by default)
but branch new <branch-name>

# Create stacked branch (anchored to another branch)
but branch new --anchor <parent-branch> <new-branch>

# Examples:
but branch new 001-user-auth
but branch new --anchor 001-user-auth sub-feature
```

### Apply/Unapply Branches

```bash
# Apply a branch to the workspace
but branch apply <branch-name>

# Unapply a branch from workspace
but branch unapply <branch-name>
```

## Mark System

The mark system controls where changes are auto-assigned.

### Mark a Branch

```bash
# Mark a branch for auto-assignment
but mark <branch-name>

# Example: Work on user-auth feature
but mark 001-user-auth
```

### Remove Mark

```bash
# Remove mark from a specific branch
but mark -d <branch-name>

# Remove all marks
but unmark
```

### Check Current Mark

```bash
# Look for "Marked" in status output
but status | grep -i marked
```

## Committing

```bash
# Commit with message
but commit -m "Your commit message"

# Commit (opens editor for message)
but commit

# Commit only assigned files (exclude unassigned)
but commit -o
```

## Push & Publish

```bash
# Push a specific branch
but push <branch-name>

# Publish PR/MR for branches
but publish
```

## Common Workflows

### Start a New Feature

```bash
# Using Speckit (creates and marks branch automatically)
./scripts/bash/create-new-feature.sh "Add user authentication"

# Manual approach:
but branch new 001-user-auth
but mark 001-user-auth
# ... make edits ...
but commit -m "Initial implementation"
```

### Continue Working on Feature

```bash
# Check available branches
but status

# Mark the feature to continue working
but mark 001-user-auth

# Make edits (auto-assign to marked branch)
# ...

# Commit when ready
but commit -m "Continue implementation"
```

### Switch Between Features

```bash
# Mark different feature
but mark 002-api-client

# Now edits go to 002-api-client
# ...

# Switch back
but mark 001-user-auth
```

### Finish a Feature

```bash
# Commit final changes
but commit -m "Complete feature"

# Push to remote
but push 001-user-auth

# Unmark (optional)
but mark -d 001-user-auth
```

### Squash Feature to Main

Use GitButler UI:
1. Open GitButler application
2. Select the feature branch
3. Use squash/rebase to merge into main

> **Note:** There is no direct CLI command for squashing. Use the GitButler UI for this operation.

## Tips

### View Branch Details

```bash
# Show commits in a branch
but branch show <branch-name>
```

### Edit Commit Messages

```bash
# Edit a commit message or rename branch
but describe <commit-or-branch>
```

### Operations Log

```bash
# View history of operations
but oplog

# Undo last operation
but undo
```

## Troubleshooting

### "No default target" Error

```bash
# Open project in GitButler UI to configure target branch
# Or check but status for project state
but status
```

### "Project not found" Error

```bash
# Initialize GitButler in the repository
but init
```

### Changes Going to Wrong Branch

```bash
# Check which branch is marked
but status

# Mark the correct branch
but mark <correct-branch>
```

## References

- [GitButler CLI Documentation](https://docs.gitbutler.com/cli-overview)
- [GitButler Commands Overview](https://docs.gitbutler.com/commands/commands-overview)
