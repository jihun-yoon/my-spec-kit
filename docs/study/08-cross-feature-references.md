# Cross-Feature Reference Design

## The Problem: Feature Isolation Breaks Multi-Feature Reference Flows

### Scenario

```
Feature 001: "Add user authentication"
  → User places prd.md in specs/001-auth/references/
  → specify → plan → tasks → implement ✓

  * User receives new architecture decision document *

Feature 002: "Add user dashboard"
  → User starts fresh feature
  → ❌ prd.md is trapped in specs/001-auth/references/
  → ❌ Architecture doc has no designated home
  → ❌ Manifest from 001 is invisible to 002
  → ❌ AI knows nothing about 001's design decisions

Feature 003: "Add notification system"
  → ❌ Same problem, worse — now TWO features' context is lost
```

### Why the Current Design Fails

Our `specs/###-feature/references/` approach is **feature-scoped**. This means:

1. **References don't carry forward** — prd.md in 001's folder is invisible to 002
2. **Manifest resets per feature** — all refs appear as NEW for every new feature
3. **Summaries are lost** — the AI-generated summaries from 001 don't help 002
4. **Duplicate copies needed** — user must manually copy refs into each feature
5. **No global reference home** — docs that span features have nowhere to live

---

## Solution: Two-Tier Reference System

### Directory Structure

```
project/
├── references/                        ← TIER 1: Project-level references
│   ├── prd.md                        (applies to all features)
│   ├── architecture-decisions.md     (added between features)
│   ├── api-standards.yaml            (company-wide standard)
│   └── .references-state.json        ← Project-level manifest
│
├── specs/
│   ├── 001-auth/
│   │   ├── references/               ← TIER 2: Feature-specific references
│   │   │   ├── auth-flow-diagram.md  (only relevant to 001)
│   │   │   └── .references-state.json ← Feature-level manifest
│   │   ├── spec.md
│   │   └── plan.md
│   │
│   └── 002-dashboard/
│       ├── references/               ← Feature 002's own refs
│       │   ├── dashboard-mockup.md   (only relevant to 002)
│       │   └── .references-state.json
│       ├── spec.md
│       └── plan.md
│
└── memory/
    └── constitution.md               ← Existing global context
```

### How Tiers Work Together

```
Command loading order:

1. Load PROJECT-LEVEL refs (references/)
   → These persist across ALL features
   → Manifest tracks incorporation per-feature

2. Load FEATURE-LEVEL refs (specs/###/references/)
   → These are specific to the current feature
   → Manifest tracks incorporation per-artifact

3. Smart loading applies to BOTH tiers independently
```

### Manifest Structure: Project-Level

The project-level manifest tracks incorporation **per feature**, not per artifact:

```json
{
  "version": 1,
  "references": {
    "prd.md": {
      "checksum": "a1b2c3",
      "size_bytes": 4200,
      "added_at": "2026-01-28T10:00:00Z",
      "incorporated_into": {
        "001-auth": {
          "artifacts": {
            "spec.md": {
              "at": "2026-01-28T10:15:00Z",
              "checksum_at_incorporation": "a1b2c3",
              "summary": "PRD defines OAuth2 with Google/GitHub, 3 user roles."
            },
            "plan.md": {
              "at": "2026-01-28T10:30:00Z",
              "checksum_at_incorporation": "a1b2c3",
              "summary": "PKCE flow chosen, JWT tokens, PostgreSQL user store."
            }
          }
        }
      }
    },
    "architecture-decisions.md": {
      "checksum": "d4e5f6",
      "size_bytes": 3100,
      "added_at": "2026-01-29T09:00:00Z",
      "incorporated_into": {}
    }
  }
}
```

### Manifest Structure: Feature-Level

Feature-level manifests remain the same as the original design (doc 07):

```json
{
  "version": 1,
  "references": {
    "auth-flow-diagram.md": {
      "checksum": "g7h8i9",
      "incorporated_into": {
        "spec.md": { "summary": "..." }
      }
    }
  }
}
```

---

## Simulation: Sequential Development with Both Tiers

### Timeline

```
Day 1: User starts project, adds PRD
Day 2: Feature 001 (auth) — full workflow
Day 3: New architecture doc arrives
Day 4: Feature 002 (dashboard) — should use PRD context + new doc
Day 5: PRD is updated (v2)
Day 6: Feature 003 (notifications) — should detect PRD change
```

---

### Day 1: Setup

```bash
mkdir -p references/
cp ~/docs/prd.md references/
```

```
references/
├── prd.md                        (4200 bytes, checksum: a1b2c3)
└── .references-state.json        (auto-initialized: empty)
```

---

### Day 2: Feature 001 — `/speckit.specify`

**Reference state check (both tiers):**

| Tier | Reference | State | Action |
|------|-----------|-------|--------|
| Project | prd.md | NEW (not in manifest) | Load full (4200 bytes) |
| Feature | (none) | — | — |

**Context cost: 4200 bytes**

After completion, **project manifest** updated:
```json
{
  "prd.md": {
    "checksum": "a1b2c3",
    "incorporated_into": {
      "001-auth": {
        "artifacts": {
          "spec.md": {
            "at": "2026-01-28T10:15:00Z",
            "checksum_at_incorporation": "a1b2c3",
            "summary": "PRD: OAuth2 with Google/GitHub, 3 roles, 3 user journeys."
          }
        }
      }
    }
  }
}
```

### Day 2 continued: Feature 001 — `/speckit.plan`

| Tier | Reference | State | Action |
|------|-----------|-------|--------|
| Project | prd.md | INCORPORATED into 001-auth/spec.md | Summary only (80 bytes) |
| Feature | auth-flow.md (user added) | NEW | Load full (1500 bytes) |

**Context cost: 1580 bytes** (vs 5700 without smart loading)

---

### Day 3: New architecture doc arrives

```bash
cp ~/docs/arch-decisions.md references/
```

Project manifest doesn't know about it yet.

---

### Day 4: Feature 002 — `/speckit.specify`

**This is the critical test.** Feature 002 starts fresh, but project-level refs persist.

**Reference state check (both tiers):**

| Tier | Reference | State for 002 | Action |
|------|-----------|---------------|--------|
| Project | prd.md | INCORPORATED into **001** (different feature) | **Cross-feature summary** (~100 bytes) |
| Project | arch-decisions.md | NEW | Load full (3100 bytes) |
| Feature | (none yet) | — | — |

**What 002's specify command receives:**

```markdown
## Reference Documents

### Project-Level References

#### Already incorporated in previous features (summaries)
- **prd.md** (incorporated in feature 001-auth):
  - spec.md: "PRD: OAuth2 with Google/GitHub, 3 roles, 3 user journeys."
  - plan.md: "PKCE flow chosen, JWT tokens, PostgreSQL user store."

  ℹ️ This reference was fully processed in feature 001-auth.
  If relevant to this feature, the summaries above provide context.
  Reply "load prd.md" if you need the full document.

#### New references (full content)
- **arch-decisions.md** — [full 3100 bytes loaded]
  (New document, not yet incorporated into any feature)
```

**Context cost: 3200 bytes** (vs 7300 if everything loaded)

**Key behavior**: prd.md isn't re-loaded because it was already digested into feature 001's artifacts. The AI gets the **summaries from 001** so it knows the project context without burning 4200 bytes.

---

### Day 5: PRD is updated

```bash
# User modifies prd.md with new requirements
echo "## Phase 2: Add social features" >> references/prd.md
```

Checksum changes from `a1b2c3` to `j0k1l2`.

---

### Day 6: Feature 003 — `/speckit.specify`

| Tier | Reference | State for 003 | Action |
|------|-----------|---------------|--------|
| Project | prd.md | **MODIFIED** since incorporation into 001 & 002 | Load full + flag changes |
| Project | arch-decisions.md | INCORPORATED into 002 | Cross-feature summary |
| Feature | (none yet) | — | — |

**What 003's specify command receives:**

```markdown
## Reference Documents

### Project-Level References

#### Modified since last incorporation (REVIEW REQUIRED)
⚠️ **prd.md** — Modified after being incorporated into features 001-auth and 002-dashboard.
Previous summaries:
- 001-auth/spec.md: "PRD: OAuth2 with Google/GitHub, 3 roles, 3 user journeys."
- 002-dashboard/spec.md: "PRD: Dashboard shows user activity, admin analytics."

Full content follows (review for new requirements):
[... full 4500 bytes of updated prd.md ...]

#### Already incorporated in previous features (summaries)
- **arch-decisions.md** (incorporated in feature 002-dashboard):
  - spec.md: "Microservices architecture, event-driven communication, shared auth service."
```

**Context cost: 4700 bytes** (vs 7600 full load)
The agent knows **exactly what changed** and what was already processed.

---

## State Detection Logic: Two-Tier Version

```
For each reference file R, current feature F, and target artifact A:

=== PROJECT-LEVEL REFERENCES ===

1. Is R in project manifest?
   NO  → State = NEW (load full)
   YES → continue

2. Has R been modified? (current checksum ≠ manifest checksum)
   YES → State = MODIFIED (load full, include all previous feature summaries)
   NO  → continue

3. Has R been incorporated into feature F?
   YES → Has R been incorporated into artifact A within feature F?
         YES → State = ALREADY_INCORPORATED (skip)
         NO  → State = INCORPORATED_ELSEWHERE (pass summary from F's other artifacts)
   NO  → Was R incorporated into ANY previous feature?
         YES → State = CROSS_FEATURE_INCORPORATED (pass cross-feature summaries)
         NO  → State = NEW (shouldn't happen, safe fallback)

=== FEATURE-LEVEL REFERENCES ===

(Same as original design from doc 07 — single-tier logic)
```

### New State: CROSS_FEATURE_INCORPORATED

This is the state that makes multi-feature development work:

| State | Meaning | Agent Receives |
|-------|---------|----------------|
| CROSS_FEATURE_INCORPORATED | Ref was used by a PREVIOUS feature, not the current one | Summaries from all previous features that used it |

This state provides:
- Context from what previous features extracted
- Enough information for the AI to decide if full loading is needed
- A hint: "Reply 'load {filename}' if you need the full document"

---

## On-Demand Full Loading

For CROSS_FEATURE_INCORPORATED refs, the agent gets summaries but may need the full doc.
The command template should include:

```markdown
### Reference Loading Protocol

For references marked as "previously incorporated":
1. Read the provided summaries
2. Determine if the current feature's requirements overlap with the summarized content
3. If the summary provides sufficient context → proceed without full loading
4. If you need details not covered by summaries → read the full file from the
   project references/ directory
5. After generating the artifact, update the project manifest with this feature's
   incorporation record
```

This gives the AI **agency to decide** when a full load is worth the context cost.

---

## Updated Script Design: `check-references.sh`

```bash
#!/usr/bin/env bash
# Two-tier reference state detection

set -e

TARGET_ARTIFACT=""
CURRENT_FEATURE=""
JSON_MODE=false

for arg in "$@"; do
    case "$arg" in
        --json) JSON_MODE=true ;;
        --target=*) TARGET_ARTIFACT="${arg#*=}" ;;
        --feature=*) CURRENT_FEATURE="${arg#*=}" ;;
    esac
done

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
eval $(get_feature_paths)

# Tier 1: Project-level references
PROJECT_REFS_DIR="$REPO_ROOT/references"
PROJECT_MANIFEST="$PROJECT_REFS_DIR/.references-state.json"

# Tier 2: Feature-level references
FEATURE_REFS_DIR="$FEATURE_DIR/references"
FEATURE_MANIFEST="$FEATURE_REFS_DIR/.references-state.json"

# Initialize manifests if missing
for manifest in "$PROJECT_MANIFEST" "$FEATURE_MANIFEST"; do
    dir=$(dirname "$manifest")
    if [[ -d "$dir" ]] && [[ ! -f "$manifest" ]]; then
        echo '{"version":1,"references":{}}' > "$manifest"
    fi
done

# Output format:
# {
#   "target": "spec.md",
#   "feature": "002-dashboard",
#   "project_refs": {
#     "load_full": ["new-doc.md"],
#     "load_modified": [{"file": "prd.md", "summaries_by_feature": {...}}],
#     "cross_feature_summaries": [{"file": "arch.md", "summaries": {...}}],
#     "skip": []
#   },
#   "feature_refs": {
#     "load_full": ["mockup.md"],
#     "summaries_only": [],
#     "skip": []
#   }
# }
```

---

## Context Budget: Multi-Feature Comparison

### Scenario: 3 project refs (prd 4200B, arch 3100B, api-std 2000B), 1 feature ref each

| Command | No Smart Loading | Feature-Only Smart | Two-Tier Smart |
|---------|------------------|--------------------|----------------|
| 001/specify | 4,200 | 4,200 | 4,200 |
| 001/plan | 4,200 | 80 | 80 |
| 002/specify | 7,300 | 7,300 | **3,280** |
| 002/plan | 7,300 | 160 | 160 |
| 003/specify (prd modified) | 9,300 | 9,300 | **4,780** |
| 003/plan | 9,300 | 240 | 240 |
| **Total** | **41,600** | **21,280** | **12,740** |

**Two-tier savings: 69% overall** (vs 49% with feature-only smart loading)

The biggest wins are at `/speckit.specify` for features 002 and 003, where cross-feature
summaries replace full re-loading of already-processed project-level references.

---

## Updated Files to Create/Modify

| File | Change |
|------|--------|
| `scripts/bash/check-references.sh` | **NEW**: Two-tier reference state detection |
| `scripts/bash/validate-references.sh` | **NEW**: Two-tier manifest validation |
| `scripts/bash/common.sh` | Add `PROJECT_REFS_DIR`, `FEATURE_REFS_DIR` to paths |
| `scripts/bash/create-new-feature.sh` | Create feature `references/` + init project `references/` if absent |
| `templates/commands/specify.md` | Two-tier loading: project refs + feature refs |
| `templates/commands/plan.md` | Two-tier loading with on-demand full load option |
| `templates/commands/clarify.md` | Access cross-feature summaries for answering |
| `templates/commands/tasks.md` | Two-tier smart loading |
| `templates/commands/implement.md` | Two-tier smart loading |

---

## Design Decision: User's Role

This is where user input is needed for implementation.

The on-demand loading behavior — where the AI sees summaries and decides whether
to read the full document — is a **meaningful design choice**. The decision logic
for when to trigger a full load vs. trust the summary is something that should be
defined in the command template. Options:

**CHOSEN: AI decides (balanced approach)**

The command template instructs the AI to:

1. Read all cross-feature summaries provided by the script
2. Evaluate whether the current feature's scope overlaps with the summarized content
3. Load full content **only when** the AI determines overlap is likely
4. Document the loading decision in the manifest for future reference

**Template guidance for the AI (included in each command):**

```markdown
## Cross-Feature Reference Loading

For references previously incorporated in other features, you receive summaries.
Decide whether to load the full document based on:

- **Load full** if: The current feature directly extends, depends on, or modifies
  functionality described in the summary. Example: Feature 002 "Add user dashboard"
  should load the full PRD if the summary mentions dashboard-related requirements.
- **Use summary only** if: The current feature is independent of the summarized
  content. Example: Feature 003 "Add email notifications" may not need the full
  auth-flow diagram from feature 001.
- **Always load full** if: The reference is marked MODIFIED (content changed).

After deciding, proceed with artifact generation. Record your loading decisions
in the manifest under this feature's incorporation record.
```

This approach trusts the AI's judgment while providing clear decision criteria.
The validation script catches any manifest inconsistencies afterward.
