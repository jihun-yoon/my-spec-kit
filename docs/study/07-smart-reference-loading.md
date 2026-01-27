# Smart Reference Loading: Design & Simulation

## Problem

Loading all reference documents every time wastes context tokens. We need the agent
to receive **only the right references** at each stage:

- **Already-incorporated refs** should NOT be re-loaded in full
- **New refs** added after an artifact was created should be loaded in full
- **Modified refs** (content changed since incorporation) should be flagged and re-loaded

---

## Design: Manifest + Summary System

### Core Concept

```
references/
├── prd.md                          ← Full reference documents
├── api-contract.yaml
├── design-doc.md
└── .references-state.json          ← Manifest tracking incorporation state
```

### Manifest Structure (`.references-state.json`)

```json
{
  "version": 1,
  "references": {
    "prd.md": {
      "checksum": "a1b2c3d4",
      "size_bytes": 4200,
      "added_at": "2026-01-28T10:00:00Z",
      "incorporated_into": {
        "spec.md": {
          "at": "2026-01-28T10:15:00Z",
          "checksum_at_incorporation": "a1b2c3d4",
          "summary": "PRD defines OAuth2 auth flow with Google/GitHub providers, user roles (admin, member, viewer), and 3 key user journeys."
        },
        "plan.md": {
          "at": "2026-01-28T10:30:00Z",
          "checksum_at_incorporation": "a1b2c3d4",
          "summary": "Technical constraints: must use PKCE flow, JWT tokens with 1h expiry, PostgreSQL for user store."
        }
      }
    },
    "api-contract.yaml": {
      "checksum": "e5f6g7h8",
      "size_bytes": 2100,
      "added_at": "2026-01-28T10:00:00Z",
      "incorporated_into": {
        "spec.md": {
          "at": "2026-01-28T10:15:00Z",
          "checksum_at_incorporation": "e5f6g7h8",
          "summary": "Defines 4 endpoints: POST /auth/login, POST /auth/register, GET /auth/me, POST /auth/refresh."
        }
      }
    },
    "design-doc.md": {
      "checksum": "i9j0k1l2",
      "size_bytes": 3500,
      "added_at": "2026-01-28T11:00:00Z",
      "incorporated_into": {}
    }
  }
}
```

### Key Fields

| Field | Purpose |
|-------|---------|
| `checksum` | Current SHA-256 hash of file content |
| `incorporated_into` | Map of artifacts that consumed this reference |
| `checksum_at_incorporation` | Hash when artifact was generated (for diff detection) |
| `summary` | 1-2 sentence summary written by AI after incorporation |

---

## Reference States

A reference can be in one of four states relative to a command:

```
┌─────────────────────────┬───────────────────────────────────────────────┐
│ State                   │ What the command receives                     │
├─────────────────────────┼───────────────────────────────────────────────┤
│ NEW                     │ Full content (never incorporated anywhere)    │
│ MODIFIED                │ Full content + diff flag + previous summary   │
│ INCORPORATED_ELSEWHERE  │ Summary only (incorporated into other artifact│
│                         │ but not into the one this command generates)  │
│ ALREADY_INCORPORATED    │ Nothing (already in the target artifact)      │
└─────────────────────────┴───────────────────────────────────────────────┘
```

### State Detection Logic

```
For each reference file R and target artifact A:

1. Is R in the manifest?
   NO  → State = NEW (load full content)
   YES → continue

2. Has R been modified? (current checksum ≠ manifest checksum)
   YES → State = MODIFIED (load full content, flag changes)
   NO  → continue

3. Has R been incorporated into artifact A?
   YES → State = ALREADY_INCORPORATED (skip entirely)
   NO  → Was R incorporated into ANY artifact?
         YES → State = INCORPORATED_ELSEWHERE (pass summary only)
         NO  → State = NEW (shouldn't happen, but safe fallback)
```

---

## Simulation: Full Workflow

### Setup

```
specs/001-oauth-auth/
├── references/
│   ├── prd.md                    (4200 bytes, checksum: a1b2c3)
│   ├── api-contract.yaml         (2100 bytes, checksum: e5f6g7)
│   └── .references-state.json    (empty manifest initially)
```

---

### Step 1: `/speckit.specify` (First command)

**Reference State Check:**
| Reference | State | Action |
|-----------|-------|--------|
| prd.md | NEW | Load full (4200 bytes) |
| api-contract.yaml | NEW | Load full (2100 bytes) |

**Context tokens used for references: ~6300 bytes worth**

**After completion**, the command writes to manifest:
```json
{
  "prd.md": {
    "checksum": "a1b2c3",
    "incorporated_into": {
      "spec.md": {
        "at": "2026-01-28T10:15:00Z",
        "checksum_at_incorporation": "a1b2c3",
        "summary": "PRD defines OAuth2 flow with Google/GitHub, 3 user roles, 3 journeys."
      }
    }
  },
  "api-contract.yaml": {
    "checksum": "e5f6g7",
    "incorporated_into": {
      "spec.md": {
        "at": "2026-01-28T10:15:00Z",
        "checksum_at_incorporation": "e5f6g7",
        "summary": "4 auth endpoints: login, register, me, refresh."
      }
    }
  }
}
```

---

### Step 2: `/speckit.clarify`

**Target artifact**: spec.md (same as specify)

**Reference State Check:**
| Reference | State | Action |
|-----------|-------|--------|
| prd.md | ALREADY_INCORPORATED into spec.md | **Skip** (0 bytes) |
| api-contract.yaml | ALREADY_INCORPORATED into spec.md | **Skip** (0 bytes) |

**Context tokens used for references: 0 bytes**

The clarify command works from spec.md which already contains the synthesized reference content.

---

### Step 3: User adds a new reference doc

```bash
cp ~/docs/security-requirements.md specs/001-oauth-auth/references/
```

Manifest doesn't know about this file yet.

---

### Step 4: `/speckit.plan`

**Target artifact**: plan.md

**Reference State Check:**
| Reference | State | Action |
|-----------|-------|--------|
| prd.md | INCORPORATED_ELSEWHERE (spec.md) | **Summary only** (~80 bytes) |
| api-contract.yaml | INCORPORATED_ELSEWHERE (spec.md) | **Summary only** (~60 bytes) |
| security-requirements.md | NEW (not in manifest) | **Load full** (3500 bytes) |

**Context tokens used for references: ~3640 bytes** (vs 9800 if all loaded)

**Savings: 63% reduction in reference context**

After completion, manifest is updated:
```json
{
  "prd.md": {
    "incorporated_into": {
      "spec.md": { "summary": "..." },
      "plan.md": { "summary": "Informed tech stack choice: PKCE flow, JWT, PostgreSQL." }
    }
  },
  "security-requirements.md": {
    "checksum": "m3n4o5",
    "incorporated_into": {
      "plan.md": {
        "summary": "Requires OWASP top-10 compliance, rate limiting, input sanitization."
      }
    }
  }
}
```

---

### Step 5: User modifies an existing reference

```bash
# User updates prd.md with new requirements
echo "## New: Add MFA support" >> specs/001-oauth-auth/references/prd.md
```

Now prd.md checksum changes from `a1b2c3` to `p6q7r8`.

---

### Step 6: `/speckit.tasks`

**Target artifact**: tasks.md

**Reference State Check:**
| Reference | State | Action |
|-----------|-------|--------|
| prd.md | **MODIFIED** (checksum changed) | **Load full + flag** (4500 bytes) |
| api-contract.yaml | INCORPORATED_ELSEWHERE | **Summary only** (~60 bytes) |
| security-requirements.md | INCORPORATED_ELSEWHERE | **Summary only** (~80 bytes) |

**Context provided to agent:**
```markdown
## Reference Documents

### Modified Since Last Incorporation (REVIEW REQUIRED)
⚠️ **prd.md** — Modified after being incorporated into spec.md and plan.md.
Previous summaries:
- spec.md: "PRD defines OAuth2 flow with Google/GitHub, 3 user roles, 3 journeys."
- plan.md: "Informed tech stack choice: PKCE flow, JWT, PostgreSQL."

Full content follows (review for new requirements):
[... full 4500 bytes of prd.md ...]

### Already Incorporated (summaries only)
- **api-contract.yaml** → "4 auth endpoints: login, register, me, refresh."
- **security-requirements.md** → "OWASP top-10, rate limiting, input sanitization."
```

**Context tokens used: ~4640 bytes** (vs 10100 if all loaded)
**Savings: 54% reduction**, and the agent knows exactly what changed.

---

### Step 7: `/speckit.implement`

**Target artifact**: (code generation)

**Reference State Check:**
| Reference | State | Action |
|-----------|-------|--------|
| prd.md | MODIFIED | **Full content** (still modified since last tasks incorporation) |
| api-contract.yaml | INCORPORATED_ELSEWHERE | **Summary only** |
| security-requirements.md | INCORPORATED_ELSEWHERE | **Summary only** |

After tasks.md incorporated the modified prd.md, the manifest would update.
Subsequent implement would see prd.md as INCORPORATED_ELSEWHERE → summary only.

---

## Context Budget Comparison

| Command | Without Smart Loading | With Smart Loading | Savings |
|---------|----------------------|-------------------|---------|
| specify | 6,300 bytes | 6,300 bytes | 0% (first load) |
| clarify | 6,300 bytes | 0 bytes | **100%** |
| plan (new ref added) | 9,800 bytes | 3,640 bytes | **63%** |
| tasks (ref modified) | 10,100 bytes | 4,640 bytes | **54%** |
| implement (after tasks) | 10,100 bytes | 140 bytes | **99%** |
| **Total** | **42,600 bytes** | **14,720 bytes** | **65%** |

---

## Script Implementation

### New Script: `check-references.sh`

```bash
#!/usr/bin/env bash
# Determines reference loading strategy for a given target artifact

set -e

TARGET_ARTIFACT=""  # e.g., "spec.md", "plan.md", "tasks.md"
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

REFS_DIR="$FEATURE_DIR/references"
MANIFEST="$REFS_DIR/.references-state.json"

# Initialize empty manifest if missing
if [[ ! -f "$MANIFEST" ]]; then
    echo '{"version":1,"references":{}}' > "$MANIFEST"
fi

# For each file in references/ (excluding manifest):
#   1. Compute current checksum
#   2. Look up in manifest
#   3. Determine state: NEW, MODIFIED, INCORPORATED_ELSEWHERE, ALREADY_INCORPORATED
#   4. Output JSON with state and content/summary

# Output format:
# {
#   "target": "plan.md",
#   "load_full": ["security-requirements.md"],
#   "load_modified": [{"file": "prd.md", "previous_summaries": {...}}],
#   "summaries_only": [{"file": "api-contract.yaml", "summary": "..."}],
#   "skip": ["already-in-plan.md"]
# }
```

### Command Integration

Each command template would include:

```markdown
## Reference Loading

1. Run `scripts/bash/check-references.sh --json --target={TARGET}` from repo root.
2. Parse JSON output into four categories:
   - **load_full**: Read these files entirely (new references)
   - **load_modified**: Read these files entirely, note they changed since last use.
     Review previous summaries to understand what was already incorporated.
   - **summaries_only**: Do NOT read these files. Use the provided 1-2 sentence
     summaries for context. These were already synthesized into earlier artifacts.
   - **skip**: Ignore entirely (already in the artifact you're generating).
3. After generating the artifact, update the manifest:
   - For each reference used, record the artifact name, timestamp, and a 1-2 sentence
     summary of what was extracted from that reference.
```

---

## Manifest Update Protocol

After each command completes:

1. For every reference file that was loaded (full or modified):
   - Write a 1-2 sentence summary of what was extracted
   - Record current checksum and timestamp
   - Add to `incorporated_into` under the target artifact

2. For any new files in `references/` not in the manifest:
   - Add entry with current checksum and empty `incorporated_into`

3. For any files in manifest but missing from `references/`:
   - Mark as `"removed": true` (don't delete from manifest to preserve history)

**Who writes the manifest? → Hybrid with Validation (CHOSEN)**

The manifest is maintained by **two actors working together**:

**1. AI Agent (writes)**:
- After generating an artifact, the AI updates `.references-state.json`
- Writes the `summary` field (only AI can produce quality summaries)
- Writes the `incorporated_into` entries with artifact name and timestamp
- Writes the `checksum` field based on file content

**2. Validation Script `validate-references.sh` (validates)**:
- Runs as a post-command step (or can be called independently)
- Recomputes checksums for all files in `references/`
- Compares against manifest checksums → warns if mismatched
- Detects files in `references/` not in manifest → warns "untracked reference"
- Detects manifest entries for files that no longer exist → warns "stale entry"
- Validates JSON structure of manifest
- Does NOT modify the manifest (read-only validation)

**Why Hybrid?**
- AI produces high-quality summaries (no regex parsing needed)
- Script catches AI mistakes (wrong checksum, forgotten files)
- Validation is deterministic and reliable
- Separation of concerns: AI = semantics, Script = mechanics

**Validation Script Output**:
```json
{
  "valid": false,
  "warnings": [
    {"type": "checksum_mismatch", "file": "prd.md", "expected": "a1b2c3", "actual": "x9y8z7"},
    {"type": "untracked_file", "file": "new-doc.md"},
    {"type": "stale_entry", "file": "deleted-doc.md"}
  ]
}
```

**Integration into Commands**:
```markdown
## Post-Artifact Validation

After updating the manifest, run `scripts/bash/validate-references.sh --json`.
If warnings are returned:
- `checksum_mismatch`: Re-read the file and update the checksum in manifest
- `untracked_file`: Add the file to manifest with state NEW
- `stale_entry`: Mark the entry as `"removed": true`
```

---

## Alternative Approaches Considered

### Approach A: Always Load Everything
- Simplest implementation
- Wastes 65% of context tokens on repeated content
- **Rejected**: Doesn't solve the user's problem

### Approach B: Inline Markers in Artifacts
- Each artifact lists `<!-- refs: prd.md(a1b2c3), api.yaml(e5f6g7) -->`
- No separate manifest file
- **Rejected**: Clutters artifacts, hard to parse, no summary support

### Approach C: Summary-Only Cache (No Manifest)
- Store `references/.summaries/prd.md.summary` alongside each ref
- Commands always load summaries, never full content
- **Rejected**: Can't detect NEW vs already-incorporated distinction

### Approach D: Manifest + Summary (CHOSEN)
- Clean separation: manifest tracks state, summaries provide cheap context
- Scripts handle state detection, AI handles summary generation
- Supports all four states: NEW, MODIFIED, INCORPORATED_ELSEWHERE, ALREADY_INCORPORATED
- **Selected**: Best balance of context savings and implementation complexity

---

## User-Facing Workflow

### Adding References Before Starting
```bash
# After speckit.specify creates the feature directory
mkdir -p specs/001-feature/references
cp ~/docs/prd.md specs/001-feature/references/
cp ~/docs/api-spec.yaml specs/001-feature/references/

# Then run speckit commands normally - references auto-detected
/speckit.plan Create plan using Node.js
```

### Adding References Mid-Workflow
```bash
# New requirement doc arrives during planning
cp ~/docs/security-req.md specs/001-feature/references/

# Next command auto-detects the new file
/speckit.tasks
# → Agent loads security-req.md in full, uses summaries for others
```

### Viewing Reference State
```bash
# Check which references are incorporated where
cat specs/001-feature/references/.references-state.json | jq .
```

---

## Files to Create/Modify

| File | Change |
|------|--------|
| `scripts/bash/check-references.sh` | **NEW**: Reference state detection script (pre-command) |
| `scripts/bash/validate-references.sh` | **NEW**: Manifest validation script (post-command) |
| `scripts/powershell/check-references.ps1` | **NEW**: PowerShell equivalent |
| `scripts/powershell/validate-references.ps1` | **NEW**: PowerShell validation equivalent |
| `scripts/bash/common.sh` | Add `REFERENCES_DIR` to `get_feature_paths()` |
| `scripts/bash/create-new-feature.sh` | Create `references/` directory |
| `scripts/bash/check-prerequisites.sh` | Add `REFERENCE_DOCS` to JSON output |
| `templates/commands/specify.md` | Add reference loading + manifest init |
| `templates/commands/plan.md` | Add smart reference loading section |
| `templates/commands/clarify.md` | Add reference-aware clarification |
| `templates/commands/tasks.md` | Add smart reference loading section |
| `templates/commands/implement.md` | Add smart reference loading section |

---

## Target Command Mapping

| Command | Target Artifact | References Needed |
|---------|----------------|-------------------|
| specify | spec.md | All (first pass) |
| clarify | spec.md | Only NEW since specify |
| plan | plan.md | NEW + summaries of spec-incorporated |
| tasks | tasks.md | MODIFIED + summaries of plan-incorporated |
| implement | (code) | MODIFIED + summaries of all prior |
| analyze | (report) | Summaries only (read-only analysis) |
| checklist | checklists/*.md | Summaries only |
