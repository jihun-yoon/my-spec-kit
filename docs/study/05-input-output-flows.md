# Input/Output Flows

## Overview

This document details the exact inputs and outputs for each command and script, showing how data flows through the Spec-Kit system.

---

## Command Input/Output Matrix

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          COMMAND INPUT/OUTPUT FLOWS                         │
├─────────────┬──────────────────────┬────────────────────────────────────────┤
│ Command     │ Inputs               │ Outputs                                │
├─────────────┼──────────────────────┼────────────────────────────────────────┤
│             │ $ARGUMENTS:          │ Files:                                 │
│ specify     │   Feature desc       │   - specs/###/spec.md                  │
│             │                      │   - specs/###/checklists/requirements  │
│             │ Script:              │                                        │
│             │   create-new-feature │ Git: Branch ###-feature-name           │
├─────────────┼──────────────────────┼────────────────────────────────────────┤
│             │ $ARGUMENTS:          │ Files:                                 │
│ clarify     │   Optional guidance  │   - specs/###/spec.md (updated)        │
│             │                      │     + Clarifications section           │
│             │ Reads:               │                                        │
│             │   - spec.md          │                                        │
├─────────────┼──────────────────────┼────────────────────────────────────────┤
│             │ $ARGUMENTS:          │ Files:                                 │
│ plan        │   Tech stack hints   │   - specs/###/plan.md                  │
│             │                      │   - specs/###/research.md              │
│             │ Script:              │   - specs/###/data-model.md            │
│             │   setup-plan         │   - specs/###/contracts/               │
│             │                      │   - specs/###/quickstart.md            │
│             │ Reads:               │   - Agent context files                │
│             │   - spec.md          │                                        │
│             │   - constitution.md  │                                        │
├─────────────┼──────────────────────┼────────────────────────────────────────┤
│             │ Reads:               │ Output:                                │
│ analyze     │   - spec.md          │   Console report (markdown)            │
│             │   - plan.md          │                                        │
│             │   - tasks.md         │ Includes:                              │
│             │   - constitution.md  │   - Findings table                     │
│             │                      │   - Coverage metrics                   │
│             │                      │   - Unmapped items                     │
├─────────────┼──────────────────────┼────────────────────────────────────────┤
│             │ $ARGUMENTS:          │ Files:                                 │
│ checklist   │   Focus domain       │   - specs/###/checklists/{domain}.md   │
│             │                      │                                        │
│             │ Reads:               │                                        │
│             │   - spec.md          │                                        │
│             │   - plan.md          │                                        │
│             │   - tasks.md         │                                        │
├─────────────┼──────────────────────┼────────────────────────────────────────┤
│             │ Script:              │ Files:                                 │
│ tasks       │   check-prerequisites│   - specs/###/tasks.md                 │
│             │                      │                                        │
│             │ Reads:               │ Format:                                │
│             │   - plan.md          │   - [ ] [T###] [P?] [Story?] Desc      │
│             │   - data-model.md    │                                        │
│             │   - contracts/       │                                        │
│             │   - research.md      │                                        │
├─────────────┼──────────────────────┼────────────────────────────────────────┤
│             │ Script:              │ Files:                                 │
│ implement   │   check-prerequisites│   - Implementation code                │
│             │                      │   - Tests                              │
│             │ Reads:               │   - .gitignore (verified/created)      │
│             │   - tasks.md         │   - .dockerignore (if needed)          │
│             │   - plan.md          │                                        │
│             │   - All artifacts    │                                        │
│             │   - checklists/      │                                        │
├─────────────┼──────────────────────┼────────────────────────────────────────┤
│             │ $ARGUMENTS:          │ Files:                                 │
│ constitution│   Principles         │   - /memory/constitution.md            │
│             │                      │                                        │
│             │ Reads:               │ Output:                                │
│             │   - Existing const.  │   - Sync impact report                 │
│             │   - All templates    │   - Updated dependent templates        │
├─────────────┼──────────────────────┼────────────────────────────────────────┤
│ taskstoissues│ Reads:              │ External:                              │
│             │   - tasks.md         │   - GitHub issues via `gh` CLI         │
└─────────────┴──────────────────────┴────────────────────────────────────────┘
```

---

## Script Input/Output Details

### create-new-feature.sh

```
INPUT:
├── Arguments
│   ├── Feature description (positional, required)
│   ├── --json (flag)
│   ├── --short-name <name> (optional)
│   └── --number N (optional)
│
└── Environment
    ├── Git state (branches, current branch)
    └── Filesystem (existing specs/ directories)

PROCESSING:
├── Parse description → extract keywords
├── Filter stop words
├── Generate branch name (max 244 bytes)
├── Find next feature number (max from branches + specs/)
└── Create directory structure

OUTPUT:
├── Git
│   └── New branch: ###-feature-name
├── Filesystem
│   └── specs/###-feature/  (directory created)
└── JSON (if --json)
    {
      "BRANCH_NAME": "###-feature-name",
      "SPEC_FILE": "/abs/path/specs/###-feature/spec.md",
      "FEATURE_NUM": "###"
    }
```

### setup-plan.sh

```
INPUT:
├── Arguments
│   ├── --json (flag)
│   └── --help (flag)
│
└── Environment
    ├── Current git branch (or SPECIFY_FEATURE)
    ├── Existing specs/ directories
    └── templates/plan-template.md

PROCESSING:
├── Validate feature branch naming
├── Find feature directory by number prefix
├── Copy plan template if not exists
└── Set SPECIFY_FEATURE environment variable

OUTPUT:
├── Filesystem
│   └── specs/###-feature/plan.md (copied from template)
└── JSON (if --json)
    {
      "FEATURE_SPEC": "/path/spec.md",
      "IMPL_PLAN": "/path/plan.md",
      "SPECS_DIR": "/path/specs/###-feature",
      "BRANCH": "###-feature-name",
      "HAS_GIT": "true"
    }
```

### check-prerequisites.sh

```
INPUT:
├── Arguments
│   ├── --json (flag)
│   ├── --require-tasks (flag)
│   ├── --include-tasks (flag)
│   └── --paths-only (flag)
│
└── Environment
    ├── Current git branch
    └── Feature directory contents

PROCESSING:
├── Validate branch naming
├── Check feature directory exists
├── Check plan.md exists
├── Check tasks.md (if required)
└── Scan for optional docs

OUTPUT (JSON):
{
  "REPO_ROOT": "/abs/path/repo",
  "BRANCH": "###-feature-name",
  "FEATURE_DIR": "/abs/path/specs/###-feature",
  "FEATURE_SPEC": "/abs/path/specs/###-feature/spec.md",
  "IMPL_PLAN": "/abs/path/specs/###-feature/plan.md",
  "TASKS": "/abs/path/specs/###-feature/tasks.md",
  "AVAILABLE_DOCS": [
    "research.md",
    "data-model.md",
    "contracts/",
    "quickstart.md"
  ]
}
```

### update-agent-context.sh

```
INPUT:
├── Arguments
│   └── Agent type (optional: claude|gemini|copilot|...)
│
└── Files
    └── specs/###-feature/plan.md (parsed for tech info)

PROCESSING:
├── Parse plan.md for:
│   ├── Language/Version
│   ├── Primary Dependencies
│   ├── Storage
│   ├── Testing frameworks
│   └── Project Type
│
└── Generate agent-specific content

OUTPUT (per agent):
├── CLAUDE.md
├── GEMINI.md
├── .github/agents/copilot-instructions.md
├── .cursor/rules/specify-rules.mdc
├── .windsurf/rules/specify-rules.md
└── etc.

CONTENT STRUCTURE:
# Active Technologies
- Language: [extracted]
- Dependencies: [extracted]
- Storage: [extracted]

# Project Structure
[tree output]

# Build Commands
[language-specific]

# Recent Changes
[last 3 features]
```

---

## Data Flow Diagram

```
                    ┌─────────────────┐
                    │   User Chat     │
                    │   ($ARGUMENTS)  │
                    └────────┬────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                    /speckit.specify                          │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ create-new-feature.sh                                │   │
│  │  → Git branch                                        │   │
│  │  → specs/###-feature/ directory                      │   │
│  └──────────────────────────────────────────────────────┘   │
│                           │                                  │
│                           ▼                                  │
│                    ┌──────────────┐                          │
│                    │   spec.md    │ ◄───────────────────────┼─── Output
│                    └──────────────┘                          │
└─────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                    /speckit.plan                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ setup-plan.sh                                        │   │
│  │  → Copies plan-template.md                           │   │
│  └──────────────────────────────────────────────────────┘   │
│                           │                                  │
│  Reads:                   │                                  │
│    - spec.md              ▼                                  │
│    - constitution.md  ┌──────────────┐                       │
│                       │   plan.md    │ ◄────────────────────┼─── Output
│                       └──────────────┘                       │
│                           │                                  │
│                           ▼                                  │
│                    ┌──────────────┐                          │
│                    │ research.md  │ ◄───────────────────────┼─── Output
│                    │ data-model   │                          │
│                    │ contracts/   │                          │
│                    │ quickstart   │                          │
│                    └──────────────┘                          │
│                           │                                  │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ update-agent-context.sh                              │   │
│  │  → CLAUDE.md, GEMINI.md, etc.                       │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                    /speckit.tasks                            │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ check-prerequisites.sh --include-tasks               │   │
│  │  → Validates plan.md exists                          │   │
│  │  → Returns AVAILABLE_DOCS                            │   │
│  └──────────────────────────────────────────────────────┘   │
│                           │                                  │
│  Reads:                   │                                  │
│    - plan.md              ▼                                  │
│    - data-model.md   ┌──────────────┐                        │
│    - contracts/      │   tasks.md   │ ◄─────────────────────┼─── Output
│    - research.md     └──────────────┘                        │
└─────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                    /speckit.implement                        │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ check-prerequisites.sh --require-tasks               │   │
│  │  → Validates tasks.md exists                         │   │
│  └──────────────────────────────────────────────────────┘   │
│                           │                                  │
│  Reads:                   │                                  │
│    - All artifacts        ▼                                  │
│    - checklists/     ┌──────────────┐                        │
│                      │ Source Code  │ ◄─────────────────────┼─── Output
│                      │    Tests     │                        │
│                      └──────────────┘                        │
└─────────────────────────────────────────────────────────────┘
```

---

## File System State Transitions

### Initial State
```
project/
└── (empty or existing code)
```

### After `specify init --ai claude --script sh`
```
project/
├── .claude/
│   └── commands/
│       ├── speckit.specify.md
│       ├── speckit.plan.md
│       ├── speckit.tasks.md
│       ├── speckit.implement.md
│       ├── speckit.clarify.md
│       ├── speckit.analyze.md
│       ├── speckit.checklist.md
│       ├── speckit.constitution.md
│       └── speckit.taskstoissues.md
├── .specify/
│   ├── memory/
│   │   └── constitution.md
│   ├── scripts/
│   │   └── bash/
│   │       ├── common.sh
│   │       ├── check-prerequisites.sh
│   │       ├── create-new-feature.sh
│   │       ├── setup-plan.sh
│   │       └── update-agent-context.sh
│   └── templates/
│       ├── spec-template.md
│       ├── plan-template.md
│       ├── tasks-template.md
│       └── checklist-template.md
└── CLAUDE.md
```

### After `/speckit.specify "Add user auth"`
```
project/
├── .claude/...
├── .specify/...
├── specs/
│   └── 001-user-auth/
│       ├── spec.md
│       └── checklists/
│           └── requirements.md
└── CLAUDE.md
```

### After `/speckit.plan`
```
project/
├── specs/
│   └── 001-user-auth/
│       ├── spec.md
│       ├── plan.md
│       ├── research.md
│       ├── data-model.md
│       ├── quickstart.md
│       ├── contracts/
│       │   └── auth-api.md
│       └── checklists/
│           └── requirements.md
└── CLAUDE.md (updated)
```

### After `/speckit.tasks`
```
project/
├── specs/
│   └── 001-user-auth/
│       ├── spec.md
│       ├── plan.md
│       ├── tasks.md      ◄── NEW
│       ├── research.md
│       ├── data-model.md
│       └── ...
└── ...
```

### After `/speckit.implement`
```
project/
├── specs/
│   └── 001-user-auth/
│       └── ...
├── src/                   ◄── NEW (implementation)
│   └── auth/
│       ├── login.ts
│       └── ...
├── tests/                 ◄── NEW
│   └── auth/
│       └── login.test.ts
├── .gitignore            ◄── Verified/created
└── ...
```

---

## JSON Communication Protocol

All scripts use consistent JSON output when `--json` flag is provided:

### Standard Fields
```json
{
  "REPO_ROOT": "/absolute/path/to/repo",
  "BRANCH": "###-feature-name",
  "FEATURE_DIR": "/absolute/path/to/specs/###-feature",
  "FEATURE_SPEC": "/absolute/path/to/specs/###-feature/spec.md",
  "IMPL_PLAN": "/absolute/path/to/specs/###-feature/plan.md",
  "TASKS": "/absolute/path/to/specs/###-feature/tasks.md",
  "HAS_GIT": "true",
  "AVAILABLE_DOCS": ["research.md", "data-model.md", "contracts/", "quickstart.md"]
}
```

### Error Handling
Scripts exit with code 1 and print error to stderr when:
- Not in a feature branch (git repos)
- Feature directory not found
- Required files missing
