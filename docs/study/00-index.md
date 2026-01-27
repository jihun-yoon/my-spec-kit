# Spec-Kit Study Documentation

## Purpose

This documentation provides a comprehensive analysis of the Spec-Kit repository structure, commands, scripts, and context handling mechanisms. The goal is to understand how the system works in order to implement a custom feature: **using provided documents as references to maintain context**.

---

## Study Documents

| Document | Description |
|----------|-------------|
| [01-architecture-overview.md](01-architecture-overview.md) | Overall repository structure, project type, supported agents |
| [02-commands-reference.md](02-commands-reference.md) | Detailed reference for all 9 Spec-Kit commands |
| [03-scripts-reference.md](03-scripts-reference.md) | Shell script documentation (Bash & PowerShell) |
| [04-context-handling.md](04-context-handling.md) | **KEY**: How context flows and the limitation to fix |
| [05-input-output-flows.md](05-input-output-flows.md) | Detailed I/O for each command and script |
| [06-implementation-guide.md](06-implementation-guide.md) | **IMPLEMENTATION**: Code changes needed for reference docs |
| [07-smart-reference-loading.md](07-smart-reference-loading.md) | **KEY**: Manifest + summary system to avoid context waste |

---

## Key Findings Summary

### The Problem
**Context is gathered only from user chat input (`$ARGUMENTS`) and auto-generated artifacts.**

The system does NOT support:
- Loading external reference documents
- Referencing existing documentation (PRDs, design docs)
- Maintaining context from attached files

### Why This Matters
1. Large features require multiple chat turns → context gets lost
2. No mechanism to reference external docs → must manually paste into spec
3. Scripts return paths but commands don't load reference docs

### The Solution (Proposed)
Add a `references/` directory with a **smart loading system** that avoids context waste:

```
specs/###-feature/
├── references/                     ← NEW: External reference docs
│   ├── prd.md                     ← Full docs placed by user
│   ├── api-spec.yaml
│   └── .references-state.json     ← Manifest tracking incorporation state
├── spec.md
├── plan.md
└── ...
```

**Smart Loading** prevents context waste by tracking which references have already
been incorporated into which artifacts. Instead of re-loading everything every time:
- **NEW** refs → load full content
- **MODIFIED** refs → load full + flag what changed
- **INCORPORATED** refs → pass 1-2 sentence summary only
- **ALREADY IN TARGET** → skip entirely

See [07-smart-reference-loading.md](docs/study/07-smart-reference-loading.md) for full design.

---

## Architecture at a Glance

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           SPEC-KIT ARCHITECTURE                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐      │
│  │   User Chat     │    │   Constitution  │    │   Reference     │      │
│  │  ($ARGUMENTS)   │    │    (Global)     │    │  Docs (TODO)    │      │
│  └────────┬────────┘    └────────┬────────┘    └────────┬────────┘      │
│           │                      │                      │                │
│           └──────────────────────┼──────────────────────┘                │
│                                  │                                       │
│                                  ▼                                       │
│  ┌───────────────────────────────────────────────────────────────┐      │
│  │                         COMMANDS                               │      │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ │      │
│  │  │ specify │→│ clarify │→│  plan   │→│  tasks  │→│implement│ │      │
│  │  └─────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────┘ │      │
│  └───────────────────────────────────────────────────────────────┘      │
│                                  │                                       │
│                                  ▼                                       │
│  ┌───────────────────────────────────────────────────────────────┐      │
│  │                          SCRIPTS                               │      │
│  │  create-new-feature │ setup-plan │ check-prereq │ agent-ctx   │      │
│  └───────────────────────────────────────────────────────────────┘      │
│                                  │                                       │
│                                  ▼                                       │
│  ┌───────────────────────────────────────────────────────────────┐      │
│  │                       ARTIFACTS                                │      │
│  │  specs/###-feature/                                            │      │
│  │    ├── spec.md          ← User stories, requirements           │      │
│  │    ├── plan.md          ← Technical architecture               │      │
│  │    ├── tasks.md         ← Implementation tasks                 │      │
│  │    ├── research.md      ← Technical decisions                  │      │
│  │    ├── data-model.md    ← Entity definitions                   │      │
│  │    ├── contracts/       ← API specifications                   │      │
│  │    └── checklists/      ← Quality validation                   │      │
│  └───────────────────────────────────────────────────────────────┘      │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Command Flow Summary

| Step | Command | Input | Output |
|------|---------|-------|--------|
| 1 | `/speckit.constitution` | Principles text | `/memory/constitution.md` |
| 2 | `/speckit.specify` | Feature description | `spec.md`, branch |
| 3 | `/speckit.clarify` | (optional) | Updated `spec.md` |
| 4 | `/speckit.plan` | Tech hints | `plan.md`, `research.md`, etc. |
| 5 | `/speckit.analyze` | - | Console report |
| 6 | `/speckit.checklist` | Domain/focus | `checklists/{name}.md` |
| 7 | `/speckit.tasks` | - | `tasks.md` |
| 8 | `/speckit.implement` | Confirmation | Code, tests |
| 9 | `/speckit.taskstoissues` | - | GitHub issues |

---

## Files to Modify for Reference Doc Feature

### Priority 1: Script Changes
```
scripts/bash/common.sh              # Add find_reference_docs()
scripts/bash/check-prerequisites.sh # Include references in output
scripts/bash/create-new-feature.sh  # Create references/ directory
scripts/powershell/common.ps1       # PowerShell equivalent
scripts/powershell/check-prerequisites.ps1
scripts/powershell/create-new-feature.ps1
```

### Priority 2: Template Changes
```
templates/spec-template.md          # Add Reference Documents section
templates/plan-template.md          # Add reference loading guidance
```

### Priority 3: Command Changes
```
templates/commands/specify.md       # Load references/ before generating spec
templates/commands/plan.md          # Include references in context
templates/commands/clarify.md       # Use references when answering
templates/commands/tasks.md         # Reference docs for task context
```

---

## Next Steps

1. **Read the identified files** to understand current implementation
2. **Design the reference document schema** (directory structure, naming)
3. **Modify scripts** to detect and return reference docs
4. **Update templates** to include reference sections
5. **Modify commands** to load and synthesize reference docs
6. **Test the workflow** with sample reference documents
