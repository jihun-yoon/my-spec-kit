# Scripts Reference

## Overview

Spec-Kit uses shell scripts for cross-platform automation. Scripts are available in both Bash (POSIX) and PowerShell variants.

---

## Script Locations

```
scripts/
├── bash/                          # POSIX shell scripts
│   ├── common.sh                 # Shared utility functions
│   ├── check-prerequisites.sh    # Prerequisite validation
│   ├── create-new-feature.sh     # Feature creation
│   ├── setup-plan.sh             # Plan setup
│   └── update-agent-context.sh   # Agent context sync
└── powershell/                    # PowerShell equivalents
    ├── common.ps1
    ├── check-prerequisites.ps1
    ├── create-new-feature.ps1
    ├── setup-plan.ps1
    └── update-agent-context.ps1
```

---

## Core Scripts

### 1. `common.sh` / `common.ps1`
**Purpose**: Shared utility functions used by all other scripts

**Key Functions (Bash)**:
```bash
get_repo_root()         # Detects repository root (git or fallback)
get_current_branch()    # Retrieves current branch name
has_git()               # Checks for git availability
check_feature_branch()  # Validates branch naming pattern (XXX-feature-name)
find_feature_dir_by_prefix()  # Locates spec directories by numeric prefix
get_feature_paths()     # Aggregates all feature-related paths
```

**Key Functions (PowerShell)**:
```powershell
Get-RepoRoot            # Repository root detection
Get-CurrentBranch       # Branch detection
Test-HasGit             # Git availability check
Test-FeatureBranch      # Branch naming validation
Get-FeaturePathsEnv     # Returns PSCustomObject with all paths
```

**Output**: Shell variable definitions:
- `REPO_ROOT` - Repository root path
- `CURRENT_BRANCH` - Current git branch
- `HAS_GIT` - true/false
- `FEATURE_DIR` - Feature directory path
- `FEATURE_SPEC` - Path to spec.md
- `IMPL_PLAN` - Path to plan.md
- `TASKS` - Path to tasks.md

---

### 2. `check-prerequisites.sh` / `check-prerequisites.ps1`
**Purpose**: Consolidated validation for workflow prerequisites

**Parameters**:
| Flag | Description |
|------|-------------|
| `--json` | Output JSON format |
| `--require-tasks` | Require tasks.md existence |
| `--include-tasks` | Include tasks.md in available docs |
| `--paths-only` | Output only path variables |
| `--help, -h` | Show help |

**Example Call**:
```bash
./check-prerequisites.sh --json --include-tasks
```

**Output (JSON mode)**:
```json
{
  "REPO_ROOT": "/path/to/repo",
  "BRANCH": "001-feature-name",
  "FEATURE_DIR": "/path/to/specs/001-feature",
  "FEATURE_SPEC": "/path/to/specs/001-feature/spec.md",
  "IMPL_PLAN": "/path/to/specs/001-feature/plan.md",
  "TASKS": "/path/to/specs/001-feature/tasks.md",
  "AVAILABLE_DOCS": ["research.md", "data-model.md", "contracts/", "quickstart.md"]
}
```

**Validations**:
- Feature branch naming (for git repos)
- Feature directory existence
- plan.md existence
- tasks.md existence (if required)

**Exit Codes**: 0 (success), 1 (validation failure)

---

### 3. `create-new-feature.sh` / `create-new-feature.ps1`
**Purpose**: Create new features with automatic branch naming and directory structure

**Parameters**:
| Flag | Description |
|------|-------------|
| Feature description | Positional argument |
| `--json` | JSON output format |
| `--short-name <name>` | Custom branch name |
| `--number N` | Explicit feature number |
| `--help, -h` | Show help |

**Example Call**:
```bash
./create-new-feature.sh --json "Add user authentication system"
```

**Output (JSON mode)**:
```json
{
  "BRANCH_NAME": "001-user-auth",
  "SPEC_FILE": "/path/to/specs/001-user-auth/spec.md",
  "FEATURE_NUM": "001"
}
```

**Key Features**:
- Intelligent branch naming (stop word filtering, length validation)
- GitHub 244-byte branch name limit enforcement
- Auto-incrementing feature numbers from git branches AND specs directory
- Supports non-git repositories (fallback to specs directory)
- Sets `SPECIFY_FEATURE` environment variable

**Branch Naming Algorithm**:
1. Extract keywords from description
2. Filter stop words (a, the, and, or, with, etc.)
3. Limit to 4 words
4. Join with hyphens
5. Prepend feature number (###-)

---

### 4. `setup-plan.sh` / `setup-plan.ps1`
**Purpose**: Create or prepare implementation plan template

**Parameters**:
| Flag | Description |
|------|-------------|
| `--json` | Output in JSON format |
| `--help, -h` | Show help |

**Example Call**:
```bash
./setup-plan.sh --json
```

**Output (JSON mode)**:
```json
{
  "FEATURE_SPEC": "/path/to/spec.md",
  "IMPL_PLAN": "/path/to/plan.md",
  "SPECS_DIR": "/path/to/specs/001-feature",
  "BRANCH": "001-feature-name",
  "HAS_GIT": "true"
}
```

**Process**:
1. Validates feature branch
2. Ensures feature directory exists
3. Copies plan-template.md (or creates empty plan.md)
4. Sets `SPECIFY_FEATURE` environment variable

---

### 5. `update-agent-context.sh` / `update-agent-context.ps1`
**Purpose**: Update AI agent context files with project metadata from plan.md

**Parameters**:
```bash
./update-agent-context.sh [agent_type]
# agent_type: claude|gemini|copilot|cursor-agent|qwen|opencode|codex|windsurf|kilocode|auggie|roo|codebuddy|amp|shai|q|bob|qoder
# Empty arg updates all existing agent files
```

**Supported Agent Files**:
| Agent | File Location |
|-------|--------------|
| Claude | `CLAUDE.md` |
| Gemini | `GEMINI.md` |
| Copilot | `.github/agents/copilot-instructions.md` |
| Cursor | `.cursor/rules/specify-rules.mdc` |
| Windsurf | `.windsurf/rules/specify-rules.md` |
| Qwen | `QWEN.md` |
| opencode/codex/q/bob/amp | `AGENTS.md` |
| CodeBuddy | `CODEBUDDY.md` |
| ... | ... |

**Parsed from plan.md**:
- Language/Version
- Primary Dependencies
- Storage systems
- Testing frameworks
- Project Type

**Output in Agent Files**:
- Active technologies (across all features)
- Project structure
- Language-specific build/test commands
- Code style guidelines
- Recent changes (last 3 features)
- Preserves manual additions between markers

---

## GitHub Actions Scripts

Located in `.github/workflows/scripts/`:

### `get-next-version.sh`
**Purpose**: Calculate next semantic version from git tags

**Output**:
```bash
latest_tag=v1.0.5
new_version=v1.0.6
```

### `check-release-exists.sh`
**Purpose**: Check if GitHub release already exists

**Input**: Version string
**Output**: Sets `GITHUB_OUTPUT` variable `exists=true|false`

### `create-release-packages.sh`
**Purpose**: Build release zip archives for all agent/script combinations

**Parameters**:
```bash
AGENTS=claude SCRIPTS=sh ./create-release-packages.sh v0.2.0
```

**Process**:
1. Creates `.genreleases/` directory
2. For each agent-script combination:
   - Copies `.specify/` structure
   - Generates agent-specific command files
   - Substitutes placeholders
   - Creates ZIP archive

**Output**: 34 ZIP files (17 agents × 2 script types)

### `generate-release-notes.sh`
**Purpose**: Generate changelog from git commit history

**Input**: New version, last tag
**Output**: `release_notes.md`

### `create-github-release.sh`
**Purpose**: Create GitHub release with all archives

**Input**: Version string
**Uses**: `gh release create` with all ZIP files

---

## Environment Variables

| Variable | Purpose | Set By |
|----------|---------|--------|
| `SPECIFY_FEATURE` | Current feature name | create-new-feature.sh |
| `GITHUB_TOKEN` / `GH_TOKEN` | GitHub API auth | User/CI |
| `AGENTS` | Release build filter | CI env |
| `SCRIPTS` | Release build filter | CI env |

---

## Script Call Chain

```
create-new-feature.sh
    ↓ (sources)
common.sh → Feature branch/spec setup
    ↓ (output)
setup-plan.sh → Creates plan.md
    ↓
update-agent-context.sh → Updates agent files from plan.md
    ↓
check-prerequisites.sh → Validates workflow state
```

---

## Error Handling

Scripts use consistent error handling:

```bash
# Bash
set -e  # Exit on error

# PowerShell
$ErrorActionPreference = "Stop"
```

**Exit Codes**:
- `0` - Success
- `1` - Validation/execution failure
