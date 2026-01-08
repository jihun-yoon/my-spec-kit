# GitButler Integration Architecture

This document describes the integration between GitButler virtual branches and the Speckit parallel Claude development workflow.

## Problem Statement

### Traditional Git Workflow Issues

When using Speckit with traditional git:

```bash
# Original behavior
./create-new-feature.sh "Add authentication"
# → Runs: git checkout -b 001-authentication
# → SWITCHES AWAY from current work!
```

**Problems:**
1. `git checkout -b` switches branches, interrupting current work
2. Cannot work on multiple features simultaneously
3. Context switching between features requires stashing/committing incomplete work

### GitButler Solution

GitButler manages branches via virtual branches, not `git checkout`:
- All branches visible in same working directory
- Changes auto-assign to marked branch
- No context switching needed

## Design Principles

### 1. Two-Level Hierarchy

```
main (trunk)
  ├── 001-feature-a (feature, anchored to main)
  ├── 002-feature-b (feature, anchored to main)
  └── 003-feature-c (feature, anchored to main)
```

**Rules:**
- All features anchor to main
- Features are parallel (not stacked under each other)
- Simple, flat structure

### 2. Mark vs Anchor

| Concept | Type | Set When | Purpose |
|---------|------|----------|---------|
| **Anchor** | Structural | Branch creation | Defines squash/merge path |
| **Mark** | Operational | Runtime (switchable) | Defines work target |

**Key insight:** Mark determines where changes auto-assign. User controls mark to direct work.

### 3. Parallel Development

Multiple Claude instances can work on different features:

```
Terminal 1: but mark 001-user-auth
Terminal 2: but mark 002-api-client
Terminal 3: but mark 003-dashboard
```

Each terminal's changes go to its marked branch.

## Architecture

### Branch Hierarchy Diagram

```
                          main (trunk)
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
   001-feature-a       002-feature-b       003-feature-c
   (anchored to main)  (anchored to main)  (anchored to main)
```

### Workflow

```
┌─────────────────────────────────────────────────────────────┐
│                 /specify "Add feature"                      │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
                    ┌───────────────┐
                    │ Create branch │
                    │ (but branch   │
                    │  new <name>)  │
                    └───────────────┘
                            │
                            ▼
                    ┌───────────────┐
                    │ Mark branch   │
                    │ (but mark     │  ← Mark BEFORE creating files!
                    │  <name>)      │
                    └───────────────┘
                            │
                            ▼
                    ┌───────────────┐
                    │ Create spec   │  ← Files auto-assign to
                    │ files         │    marked branch
                    └───────────────┘
                            │
                            ▼
                    ┌───────────────────────┐
                    │ User edits            │
                    │ (auto-assign to mark) │
                    └───────────────────────┘
                            │
                            ▼
                    ┌───────────────┐
                    │ Commit        │
                    │ (but commit)  │
                    └───────────────┘
                            │
                            ▼
                    ┌───────────────┐
                    │ Unmark when   │
                    │ done          │
                    └───────────────┘
```

## Implementation

### File Structure

```
spec-kit-parallel-claude/
├── .claude/
│   └── settings.json           # Permissions (no hooks)
├── scripts/bash/
│   └── create-new-feature.sh   # Feature creation with GitButler support
├── docs/
│   ├── architecture/
│   │   └── gitbutler-integration.md  # This document
│   └── reference/
│       └── but-cli-commands.md       # CLI quick reference
└── README.md                   # Fork documentation
```

### GitButler Auto-Detection

The `create-new-feature.sh` script auto-detects GitButler:

```bash
# Auto-detect GitButler: if .git/gitbutler/ exists, default to GitButler mode
if [ -d ".git/gitbutler" ]; then
    GITBUTLER_MODE=true
fi
```

Users can override:
- `--gitbutler` - Explicitly enable GitButler mode
- `--no-gitbutler` - Opt out to traditional git

## Workflows

### Creating a Feature

```bash
# With GitButler (default when .git/gitbutler/ exists)
./create-new-feature.sh "Add user authentication"

# Traditional git (explicit opt-out)
./create-new-feature.sh "Add user authentication" --no-gitbutler
```

### Working with Claude

1. Run `/specify` → Branch created and marked
2. Make edits → Auto-assign to marked branch
3. Commit → `but commit -m "message"`
4. Unmark → `but mark -d <branch-name>`

### Continuing Work on Existing Feature

```bash
# Mark the feature you want to work on
but mark 001-user-auth

# Make edits (they auto-assign)
# ...

# Commit when ready
but commit -m "Continue implementation"
```

### Squashing to Main

Use GitButler UI to squash feature commits:
1. Open GitButler
2. Select the feature branch
3. Use squash/rebase options

## Design Decisions

### Why No Hooks?

**Considered:** Custom hooks for session management

**Rejected because:**
1. Adds complexity
2. GitButler's mark system already handles auto-assignment
3. Users understand mark-based workflow better
4. Simpler = fewer failure modes

**Result:** Use GitButler natively with mark system.

### Why Two Levels Only?

**Considered:** 3-level hierarchy (main → feature → session)

**Rejected because:**
1. Sessions add complexity without clear benefit
2. Mark already enables continuing previous work
3. Flat structure is easier to understand
4. Squash path is clearer

**Result:** main → feature only.

### Why Keep Mark After Creation?

**Previous:** Unmark after `/specify` to prevent accidental assignment

**Current:** Keep marked so user can continue working immediately

**Rationale:**
- Immediate workflow: create feature → start working
- User controls when to unmark
- More intuitive: created branch = working branch

## Migration from Traditional Git

### Step 1: Install GitButler CLI

```bash
brew install gitbutlerapp/tap/but
```

### Step 2: Initialize GitButler

```bash
cd /path/to/project
but init
```

### Step 3: Use New Workflow

```bash
# New features automatically use GitButler
./create-new-feature.sh "Feature description"

# Opt-out if needed
./create-new-feature.sh "Emergency fix" --no-gitbutler
```

### Rollback

The `--no-gitbutler` flag provides immediate fallback. Existing git history remains intact.

## References

- [GitButler CLI Documentation](https://docs.gitbutler.com/cli-overview)
- [GitButler Commands Overview](https://docs.gitbutler.com/commands/commands-overview)
