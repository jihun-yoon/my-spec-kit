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
| [04-context-handling.md](04-context-handling.md) | How context flows and the limitation to fix |
| [05-input-output-flows.md](05-input-output-flows.md) | Detailed I/O for each command and script |
| [06-implementation-guide.md](06-implementation-guide.md) | Initial implementation ideas (superseded by 07) |
| [07-smart-reference-loading.md](07-smart-reference-loading.md) | **FINAL DESIGN**: Sprint-based, two-stage loading |
| [08-cross-feature-references.md](08-cross-feature-references.md) | Historical: cross-feature ideas (superseded) |
| [09-revised-reference-design.md](09-revised-reference-design.md) | Historical: git inheritance analysis (superseded) |

---

## Final Design Summary

### The Problem
**Context is gathered only from user chat input (`$ARGUMENTS`) and auto-generated artifacts.**

The system does NOT support:
- Loading external reference documents (PRDs, design docs)
- Maintaining context across commands
- Avoiding redundant loading of already-processed docs

### The Solution

**Sprint-based reference organization with two-stage loading:**

```
project/
├── references/
│   ├── .current-sprint           ← Optional: override auto-detection
│   ├── sprint-1/                 ← Sprint 1 docs
│   │   ├── prd.md
│   │   ├── architecture.md
│   │   └── .references-state.json
│   └── sprint-3/                 ← Sprint 3 docs (sprint-2 had none)
│       └── security-req.md
│
└── specs/
    ├── 001-auth/
    ├── 002-dashboard/
    └── ...
```

---

## Key Design Decisions

### 1. Sprint-Based Organization
- References grouped by development sprint (`references/sprint-N/`)
- Auto-detect highest sprint with files
- Optional `.current-sprint` file to override
- Sprints without docs are valid (normal speckit behavior)

### 2. Two-Stage Loading (WHAT + HOW)
| Command | Stage | Reference Loading |
|---------|-------|-------------------|
| `specify` | WHAT (requirements) | **Load** |
| `clarify` | Refinement | Skip |
| `plan` | HOW (architecture) | **Load** |
| `tasks` | Execution | Skip |
| `implement` | Execution | Skip |

### 3. No Summaries
- Artifacts ARE the summaries (spec.md synthesizes PRD, plan.md synthesizes architecture)
- Eliminates AI-generated summary complexity
- Simpler manifest structure

### 4. Three States Only
| State | Condition | Action |
|-------|-----------|--------|
| `NEW` | Not in manifest for this artifact | Load full |
| `MODIFIED` | Checksum changed | Load full |
| `INCORPORATED` | Already loaded for this artifact | Skip |

### 5. Per-Feature, Per-Artifact Tracking
```json
{
  "references": {
    "prd.md": {
      "checksum": "sha256:...",
      "incorporated_into": {
        "001-auth": { "spec.md": true, "plan.md": true },
        "002-dashboard": { "spec.md": true }
      }
    }
  }
}
```

---

## Context Savings

| Scenario | Without Smart Loading | With Smart Loading | Savings |
|----------|----------------------|-------------------|---------|
| 1 feature, 5 commands | 40KB | 16KB | **60%** |
| 2 features, 10 commands | 80KB | 32KB | **60%** |
| Sprint without docs | 0 | 0 | — |

---

## User Workflow

```bash
# Sprint 1: Add design docs
mkdir -p references/sprint-1
cp ~/docs/prd.md references/sprint-1/
cp ~/docs/architecture.md references/sprint-1/

# Build features (docs auto-loaded at specify + plan)
/speckit.specify "Build auth"      # Loads docs → spec.md
/speckit.plan                      # Loads docs → plan.md
/speckit.tasks                     # Skips (reads artifacts)
/speckit.implement                 # Skips (reads tasks.md)

# Sprint 2: No docs needed
echo "sprint-2" > references/.current-sprint
/speckit.specify "Add logging"     # Normal speckit, no refs

# Sprint 3: New requirements
mkdir -p references/sprint-3
cp ~/docs/security-req.md references/sprint-3/
/speckit.specify "Add security"    # Auto-detects sprint-3
```

---

## Architecture with References

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           SPEC-KIT ARCHITECTURE                          │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐      │
│  │   User Chat     │    │   Constitution  │    │   References    │      │
│  │  ($ARGUMENTS)   │    │    (Global)     │    │ (Sprint-based)  │      │
│  └────────┬────────┘    └────────┬────────┘    └────────┬────────┘      │
│           │                      │                      │                │
│           └──────────────────────┼──────────────────────┘                │
│                                  │                                       │
│                                  ▼                                       │
│  ┌───────────────────────────────────────────────────────────────┐      │
│  │                         COMMANDS                               │      │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ │      │
│  │  │ specify │→│ clarify │→│  plan   │→│  tasks  │→│implement│ │      │
│  │  │ (LOAD)  │ │ (skip)  │ │ (LOAD)  │ │ (skip)  │ │ (skip)  │ │      │
│  │  └─────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────┘ │      │
│  └───────────────────────────────────────────────────────────────┘      │
│                                  │                                       │
│                                  ▼                                       │
│  ┌───────────────────────────────────────────────────────────────┐      │
│  │                          SCRIPTS                               │      │
│  │  check-references │ update-manifest │ create-feature │ ...    │      │
│  └───────────────────────────────────────────────────────────────┘      │
│                                  │                                       │
│                                  ▼                                       │
│  ┌───────────────────────────────────────────────────────────────┐      │
│  │                       ARTIFACTS                                │      │
│  │  specs/###-feature/                                            │      │
│  │    ├── spec.md          ← WHAT (from refs + user input)        │      │
│  │    ├── plan.md          ← HOW (from refs + spec.md)            │      │
│  │    ├── tasks.md         ← STEPS (from spec.md + plan.md)       │      │
│  │    └── ...                                                     │      │
│  └───────────────────────────────────────────────────────────────┘      │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Files to Create/Modify

### Phase 1: MVP
| File | Change |
|------|--------|
| `scripts/bash/check-references.sh` | **NEW**: Command-aware state detection |
| `scripts/bash/update-manifest.sh` | **NEW**: Per-artifact manifest update |
| `templates/commands/specify.md` | Add reference loading protocol |
| `templates/commands/plan.md` | Add reference loading protocol |

### Phase 2: Full Coverage
| File | Change |
|------|--------|
| `scripts/bash/common.sh` | Add `REFS_BASE` to paths |
| `scripts/powershell/*` | PowerShell equivalents |
| Validation script | Manifest integrity checks |

---

## Implementation Phases

### Phase 1: MVP (Ship First)
- `check-references.sh` with command classification
- Per-artifact tracking in manifest
- Integration into `specify.md` and `plan.md`
- Auto-detect current sprint

### Phase 2: Full Coverage
- `update-manifest.sh` for manifest updates
- `--refs` filter flag for power users
- Validation script

### Phase 3: Enhancements (If Needed)
- Observability and metrics
- Sprint comparison tools

**Start with Phase 1. Add complexity only when users hit real problems.**
