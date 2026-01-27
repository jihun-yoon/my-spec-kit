# Revised Reference Design: Git Branch Inheritance

## Correction

Documents 07 and 08 assumed features are isolated on disk. This is wrong.

`create-new-feature.sh` line 275:
```bash
git checkout -b "$BRANCH_NAME"
```

This branches from the **current branch**, so `002-dashboard` inherits ALL files
from `001-auth` — including `specs/001-auth/references/`, `specs/001-auth/spec.md`,
all implemented code, everything.

### What We Got Wrong

| Assumption | Reality |
|------------|---------|
| Feature 002 can't see 001's files | 002's branch contains ALL of 001's files |
| Need project-level `references/` for persistence | Previous features' refs already persist via git |
| Cross-feature context is lost | It's on disk — commands just don't look for it |

### What's Actually Broken

The problem is **not file access** — it's **script scoping**:

```
get_feature_paths() → FEATURE_DIR = specs/002-dashboard/
                      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                      Locked to current feature prefix.
                      specs/001-auth/ is invisible to scripts.
```

No script scans `specs/*/references/` — they only look at `specs/###-current/`.

---

## Revised Design: Scan All Features' References

### Approach

Instead of a separate project-level `references/` directory, **scan all
`specs/*/references/` directories** on the current branch. Previous features'
refs are already there because of git branch inheritance.

Keep project-level `references/` only for docs added BEFORE any feature exists
(or docs not tied to any specific feature).

### Revised Directory Structure

```
project/
├── references/                      ← Project-level (for pre-feature docs only)
│   ├── company-api-standard.yaml    (not tied to any feature)
│   └── .references-state.json
│
├── specs/
│   ├── 001-auth/
│   │   ├── references/              ← Feature 001's refs (inherited by 002+)
│   │   │   ├── prd.md
│   │   │   └── auth-flow.md
│   │   ├── spec.md
│   │   └── plan.md
│   │
│   └── 002-dashboard/               ← Current feature
│       ├── references/              ← Feature 002's own refs
│       │   └── dashboard-mockup.md
│       ├── spec.md
│       └── plan.md
```

On branch `002-dashboard`, ALL of these directories exist and are readable.

### Revised Script: `check-references.sh`

```bash
#!/usr/bin/env bash
# Scan all feature references + project references
# Outputs categorized reference loading plan

set -e

TARGET_ARTIFACT=""
JSON_MODE=false

for arg in "$@"; do
    case "$arg" in
        --json) JSON_MODE=true ;;
        --target=*) TARGET_ARTIFACT="${arg#*=}" ;;
    esac
done

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
eval $(get_feature_paths)

REPO_ROOT_VAL="$REPO_ROOT"
SPECS_DIR="$REPO_ROOT_VAL/specs"
CURRENT_FEATURE_PREFIX=""

# Extract current feature prefix (e.g., "002" from "002-dashboard")
if [[ "$CURRENT_BRANCH" =~ ^([0-9]{3})- ]]; then
    CURRENT_FEATURE_PREFIX="${BASH_REMATCH[1]}"
fi

# ── Collect references from THREE sources ──

# 1. Project-level references (references/ at repo root)
PROJECT_REFS_DIR="$REPO_ROOT_VAL/references"

# 2. Current feature's references
CURRENT_REFS_DIR="$FEATURE_DIR/references"

# 3. Previous features' references (specs/001-*/references/, specs/002-*/references/, ...)
#    Only scan features with LOWER prefix than current
PREVIOUS_FEATURE_REFS=()
if [[ -d "$SPECS_DIR" ]]; then
    for feature_dir in "$SPECS_DIR"/[0-9][0-9][0-9]-*; do
        [[ -d "$feature_dir" ]] || continue
        feature_name=$(basename "$feature_dir")

        # Extract prefix number
        if [[ "$feature_name" =~ ^([0-9]{3})- ]]; then
            prefix="${BASH_REMATCH[1]}"
            # Only include PREVIOUS features (lower number than current)
            if [[ "$((10#$prefix))" -lt "$((10#$CURRENT_FEATURE_PREFIX))" ]]; then
                refs_dir="$feature_dir/references"
                if [[ -d "$refs_dir" ]] && [[ -n "$(ls -A "$refs_dir" 2>/dev/null)" ]]; then
                    PREVIOUS_FEATURE_REFS+=("$feature_name")
                fi
            fi
        fi
    done
fi

# Output JSON with three tiers:
# {
#   "target": "spec.md",
#   "current_feature": "002-dashboard",
#   "project_refs": {
#     "dir": "/path/references",
#     "files": ["company-api-standard.yaml"],
#     "states": {...}
#   },
#   "current_feature_refs": {
#     "dir": "/path/specs/002-dashboard/references",
#     "files": ["dashboard-mockup.md"],
#     "states": {...}
#   },
#   "previous_feature_refs": [
#     {
#       "feature": "001-auth",
#       "dir": "/path/specs/001-auth/references",
#       "files": ["prd.md", "auth-flow.md"],
#       "states": {...}
#     }
#   ]
# }
```

### Key Change: Script Scans Previous Features

The critical difference from the original design:

```
BEFORE (original design):
  get_feature_paths() → only specs/002-dashboard/
  check-references.sh → only specs/002-dashboard/references/

AFTER (revised design):
  check-references.sh → scans:
    1. references/                         (project-level)
    2. specs/002-dashboard/references/     (current feature)
    3. specs/001-auth/references/          (previous features, prefix < current)
```

---

## Revised State Detection

For previous features' references, the state logic simplifies because we know
those refs were already used in earlier features:

```
For reference R in previous feature F_prev:

1. Does current feature's manifest already record R?
   YES → Was checksum same?
         YES → ALREADY_INCORPORATED (skip)
         NO  → MODIFIED (load full)
   NO  → continue

2. Does F_prev have a manifest with summaries for R?
   YES → INHERITED (pass F_prev's summaries, AI decides if full load needed)
   NO  → INHERITED_NO_SUMMARY (load full — no manifest means old feature)
```

### New State: INHERITED

| State | When | What AI Receives |
|-------|------|------------------|
| INHERITED | Ref from a previous feature with manifest summaries | Summaries from previous feature's artifacts |
| INHERITED_NO_SUMMARY | Ref from a previous feature, no manifest | Full content (can't determine what was extracted) |

---

## Revised Simulation

### Setup: Feature 001 complete, starting Feature 002

Branch `002-dashboard` contains:
```
specs/
├── 001-auth/
│   ├── references/
│   │   ├── prd.md                      (4200 bytes)
│   │   ├── auth-flow.md                (1500 bytes)
│   │   └── .references-state.json      (has summaries from 001's workflow)
│   ├── spec.md
│   ├── plan.md
│   └── tasks.md
│
└── 002-dashboard/                       (just created, mostly empty)
    ├── references/                      (empty or user adds new refs here)
    └── spec.md                          (template)
```

### Feature 002: `/speckit.specify "Add user dashboard"`

**check-references.sh scans:**

| Source | Reference | State | Action |
|--------|-----------|-------|--------|
| 001-auth/references/ | prd.md | INHERITED (has summaries) | Pass summaries (~160 bytes) |
| 001-auth/references/ | auth-flow.md | INHERITED (has summaries) | Pass summaries (~80 bytes) |
| 002-dashboard/references/ | (none yet) | — | — |
| project references/ | (none) | — | — |

**What the AI receives:**

```markdown
## Reference Documents

### Inherited from previous features

**From feature 001-auth:**

- **prd.md** (4200 bytes, inherited from 001-auth):
  - → spec.md summary: "PRD defines OAuth2 with Google/GitHub, 3 user roles, 3 journeys."
  - → plan.md summary: "PKCE flow chosen, JWT tokens, PostgreSQL user store."
  Path: specs/001-auth/references/prd.md (read full if needed for this feature)

- **auth-flow.md** (1500 bytes, inherited from 001-auth):
  - → spec.md summary: "OAuth2 authorization code flow with PKCE, redirect handling."
  Path: specs/001-auth/references/auth-flow.md (read full if needed)

### Current feature references
(none)
```

**AI decides:** "Dashboard needs user role info from PRD → load full prd.md.
Auth flow diagram is not relevant to dashboard → use summary only."

**Context cost: ~4440 bytes** (prd.md full + auth-flow summary)
**Without smart loading: 5700 bytes** (both full)
**Savings: 22%** (modest here because AI chose to load prd.md, but grows with more refs)

### User adds new reference mid-feature

```bash
cp ~/docs/dashboard-wireframe.md specs/002-dashboard/references/
```

### Feature 002: `/speckit.plan`

| Source | Reference | State | Action |
|--------|-----------|-------|--------|
| 001-auth/references/ | prd.md | INHERITED + already loaded in 002's specify | Summary only |
| 001-auth/references/ | auth-flow.md | INHERITED (summary only in specify) | Summary only |
| 002-dashboard/references/ | dashboard-wireframe.md | NEW | Load full |

**Context cost: ~2340 bytes** (wireframe full + 2 summaries)

---

## What About Project-Level `references/`?

Still useful for a narrow case:

**When the user has documents BEFORE creating any feature:**
```bash
# Day 1: Set up project
specify init my-project --ai claude --script sh

# Add reference docs before any feature
mkdir -p references/
cp ~/docs/company-api-standards.yaml references/
cp ~/docs/product-roadmap.md references/

# Day 2: Start first feature
/speckit.specify "Add user authentication"
# → check-references.sh finds references/company-api-standards.yaml
# → Also finds references/product-roadmap.md
# → Both loaded as NEW (no previous feature to inherit from)
```

**After feature 001 is done**, those project-level refs would also be on the 002 branch
(since they were committed). But having them at project level makes their intent clear:
"these apply to the whole project, not just one feature."

### Rule of Thumb

| Reference Type | Where to Put It |
|----------------|-----------------|
| Applies to one feature | `specs/###-feature/references/` |
| Applies to all/many features | `references/` at project root |
| Added before any feature exists | `references/` at project root |
| Added during a feature | Current feature's `references/` |

---

## Manifest Strategy (Revised)

### One Manifest Per References Directory

Each `references/` directory has its own `.references-state.json`:

```
references/.references-state.json                    ← Project-level manifest
specs/001-auth/references/.references-state.json     ← Feature 001's manifest
specs/002-dashboard/references/.references-state.json ← Feature 002's manifest
```

### Cross-Feature Reading

When feature 002 scans feature 001's references:
- It reads `specs/001-auth/references/.references-state.json`
- Extracts summaries from 001's incorporation records
- Does NOT write to 001's manifest (read-only for previous features)
- Writes incorporation records to its OWN manifest

This keeps each feature's manifest as a clean record of what IT incorporated.

### Feature 002's Manifest After Specify

```json
{
  "version": 1,
  "references": {
    "inherited:001-auth/prd.md": {
      "source": "specs/001-auth/references/prd.md",
      "checksum": "a1b2c3",
      "loading_decision": "full",
      "reason": "Dashboard feature needs user role definitions from PRD",
      "incorporated_into": {
        "spec.md": {
          "at": "2026-01-29T10:15:00Z",
          "summary": "Extracted user roles (admin, member, viewer) and dashboard-related journeys."
        }
      }
    },
    "inherited:001-auth/auth-flow.md": {
      "source": "specs/001-auth/references/auth-flow.md",
      "checksum": "d4e5f6",
      "loading_decision": "summary_only",
      "reason": "Auth flow not directly relevant to dashboard feature",
      "incorporated_into": {}
    }
  }
}
```

Note the `inherited:` prefix and `loading_decision` field — this records the AI's
choice and makes it auditable.

---

## Updated Files to Create/Modify

| File | Change |
|------|--------|
| `scripts/bash/check-references.sh` | **NEW**: Three-source scanner (project + current + previous features) |
| `scripts/bash/validate-references.sh` | **NEW**: Multi-manifest validation |
| `scripts/bash/common.sh` | Add `REFERENCES_DIR`, `SPECS_DIR` to `get_feature_paths()` |
| `scripts/bash/create-new-feature.sh` | Create feature `references/` dir |
| `scripts/powershell/*` | PowerShell equivalents of above |
| `templates/commands/specify.md` | Three-source reference loading + AI decision protocol |
| `templates/commands/plan.md` | Three-source loading with inherited summary support |
| `templates/commands/clarify.md` | Can reference inherited docs for answering |
| `templates/commands/tasks.md` | Three-source loading |
| `templates/commands/implement.md` | Three-source loading |

---

## Summary of Design Evolution

| Version | Approach | Problem |
|---------|----------|---------|
| Doc 06 | Always load all refs | Context waste |
| Doc 07 | Manifest + smart states (single feature) | No cross-feature support |
| Doc 08 | Two-tier: project + feature refs | Assumed features are isolated on disk |
| **Doc 09** | **Three-source: project + current + inherited** | **Correct model — git branches inherit** |

### Final Architecture

```
check-references.sh scans:

  ┌─ 1. references/ (project root)
  │     For: pre-feature docs, project-wide standards
  │
  ├─ 2. specs/###-current/references/ (current feature)
  │     For: feature-specific docs added by user
  │
  └─ 3. specs/001-*/references/, specs/002-*/references/, ...
        For: previous features' refs (inherited via git)
        Read their manifests for summaries (read-only)
        AI decides: load full or trust summary
```
