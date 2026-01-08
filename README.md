# Spec Kit - Parallel Claude Edition

A fork of [Spec Kit](https://github.com/github/spec-kit) with GitButler integration for parallel Claude development.

## What's Different?

This fork adds **GitButler virtual branch support** to enable:

- **Multiple Claude instances** working on different features simultaneously
- **No context switching** - work on multiple features in the same directory
- **Mark-based workflow** - control where changes go with `but mark`

## Quick Start

### 1. Install Prerequisites

```bash
# Install GitButler CLI
brew install gitbutlerapp/tap/but

# Install Specify CLI
uv tool install specify-cli --from git+https://github.com/jihun-yoon/spec-kit-parallel-claude.git
```

### 2. Initialize Project

```bash
# Create new project
specify init <PROJECT_NAME> --ai claude

# Initialize GitButler
cd <PROJECT_NAME>
but init
```

### 3. Create a Feature

```bash
# GitButler mode is auto-detected when .git/gitbutler/ exists
./scripts/bash/create-new-feature.sh "Add user authentication"

# Or use /speckit.specify command in Claude
/speckit.specify Add user authentication
```

The script:
1. Creates a virtual branch (e.g., `001-user-auth`)
2. Creates spec files in `specs/001-user-auth/`
3. **Marks the branch** so your edits auto-assign to it

### 4. Work with Claude

After `/specify`, the feature branch is marked. All edits auto-assign to it.

```bash
# Check current mark
but status  # Look for "Marked" indicator

# Commit when ready
but commit -m "Implement user auth"

# When done, unmark
but mark -d 001-user-auth
```

## Parallel Development

Work on multiple features simultaneously by managing marks:

```bash
# Terminal 1: Working on 001-user-auth (marked)
but mark 001-user-auth
# ... Claude edits go to 001-user-auth

# Terminal 2: Switch to 002-api-client
but mark 002-api-client
# ... Claude edits go to 002-api-client
```

Each terminal can have a different branch marked. Changes auto-assign to the marked branch.

## Key Concepts

| Concept | Description |
|---------|-------------|
| **Feature Branch** | Main work unit (e.g., `001-user-auth`), anchored to main |
| **Mark** | Target for auto-assignment of changes |
| **Anchor** | Structural relationship (feature → main) |

## Branch Hierarchy

```
main
  ├── 001-user-auth (feature)
  ├── 002-api-client (feature)
  └── 003-dashboard (feature)
```

Features are parallel, all anchored to main.

## Common Commands

```bash
# Create feature (auto-marks it)
./scripts/bash/create-new-feature.sh "Feature description"

# Check workspace status
but status

# Mark a branch for work
but mark <branch-name>

# Unmark current branch
but mark -d <branch-name>

# Commit changes
but commit -m "Your message"

# Push to remote
but push <branch-name>
```

## Documentation

- [Architecture Design](docs/architecture/gitbutler-integration.md) - How it works
- [CLI Quick Reference](docs/reference/but-cli-commands.md) - `but` command reference
- [Original Spec Kit Docs](https://github.github.io/spec-kit/) - Full Speckit documentation

## Design Principles

1. **2 levels**: main → features (parallel)
2. **Mark = operational** (switchable, defines work target)
3. **Anchor = structural** (set at creation, defines merge path)
4. **No hooks** - simple, predictable workflow

## Migration from Traditional Git

1. Install GitButler: `brew install gitbutlerapp/tap/but`
2. Initialize: `but init`
3. Use new workflow - features automatically use GitButler
4. Opt-out with `--no-gitbutler` if needed

## License

MIT - Same as original Spec Kit

## Acknowledgements

- [GitHub Spec Kit](https://github.com/github/spec-kit) - Original toolkit
- [GitButler](https://gitbutler.com/) - Virtual branch management
- [Claude Code](https://claude.ai/code) - AI coding assistant
