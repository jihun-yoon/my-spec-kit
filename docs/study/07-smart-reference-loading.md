# Smart Reference Loading: Design & Simulation

## Problem

Loading all reference documents every time wastes context tokens. We need the agent
to receive **only the right references** at each stage:

- **Already-incorporated refs** should NOT be re-loaded
- **New refs** added mid-sprint should be loaded in full
- **Modified refs** (content changed) should be re-loaded
- **No refs** is fine — system works without reference docs

---

## Design Principles

1. **Sprint-based organization** — references grouped by development sprint
2. **Fully optional** — works with or without reference docs
3. **No summaries** — artifacts themselves are the synthesis
4. **Simple states** — only 3 states: NEW, MODIFIED, INCORPORATED
5. **Two context stages** — load at specify (WHAT) and plan (HOW), skip rest

---

## Key Insight: WHAT vs HOW Stages

Reference docs contain different types of information:

| Doc Type | Content | Needed By |
|----------|---------|-----------|
| PRD, requirements | WHAT to build | `specify` |
| Architecture, design | HOW to build | `plan` |
| API specs, contracts | INTERFACE details | Read from plan.md |
| Security requirements | CONSTRAINTS | Read from spec.md/plan.md |

**Solution:** Load docs at both `specify` and `plan` stages, skip for execution stages.

```
specify → Load docs → writes spec.md (WHAT)
clarify → Skip      → refines spec.md
plan    → Load docs → writes plan.md (HOW)
tasks   → Skip      → reads spec.md + plan.md
implement → Skip    → reads tasks.md
```

---

## Command Classification

| Command | Stage Type | Reference Loading |
|---------|------------|-------------------|
| `specify` | Context-gathering (WHAT) | **Load** |
| `clarify` | Refinement | Skip (reads spec.md) |
| `plan` | Context-gathering (HOW) | **Load** |
| `analyze` | Analysis | Skip (reads artifacts) |
| `checklist` | Validation | Skip (reads artifacts) |
| `tasks` | Execution planning | Skip (reads spec.md + plan.md) |
| `implement` | Execution | Skip (reads tasks.md) |
| `taskstoissues` | Export | Skip (reads tasks.md) |

---

## Directory Structure

### Sprint-Based References (Optional)

```
project/
├── references/
│   ├── .current-sprint           ← Optional: override auto-detection
│   │
│   ├── sprint-1/                 ← Sprint 1 docs
│   │   ├── prd.md
│   │   ├── architecture.md
│   │   └── .references-state.json
│   │
│   ├── sprint-3/                 ← Sprint 3 docs (sprint-2 had none)
│   │   ├── security-req.md
│   │   └── .references-state.json
│   │
│   └── _archive/                 ← Historical docs (ignored by script)
│       └── old-prd.md
│
└── specs/
    ├── 001-auth/
    ├── 002-dashboard/
    └── ...
```

### No References (Also Valid)

```
project/
├── references/                   ← Empty or doesn't exist
└── specs/
    └── 001-feature/              ← Normal speckit, no refs
```

---

## Sprint Detection Logic

```
1. Does references/.current-sprint exist?
   YES → Use specified sprint
   NO  → Continue to auto-detect

2. Find sprint directories (references/sprint-*/)
   NONE → No reference loading (normal speckit)
   FOUND → Use highest numbered sprint with files

3. Does selected sprint directory have files?
   NO  → No reference loading
   YES → Load using state machine
```

---

## Manifest Structure (`.references-state.json`)

### Per-Feature, Per-Artifact Tracking

```json
{
  "version": 1,
  "sprint": "sprint-1",
  "references": {
    "prd.md": {
      "checksum": "sha256:a1b2c3d4e5f6...",
      "size_bytes": 5000,
      "incorporated_into": {
        "001-auth": {
          "spec.md": true,
          "plan.md": true
        },
        "002-dashboard": {
          "spec.md": true
        }
      }
    }
  }
}
```

**What's tracked:**
- `checksum` — detect modifications
- `size_bytes` — logging/debugging
- `incorporated_into` — map of feature → artifact → boolean

---

## Reference States

Only 3 states:

| State | Condition | Action |
|-------|-----------|--------|
| `NEW` | Not incorporated into this artifact | Load full |
| `MODIFIED` | Checksum changed since last load | Load full |
| `INCORPORATED` | Already loaded for this artifact | Skip |

### State Detection Logic

```
For reference R, feature F, artifact A, command C:

1. Is C a context-gathering command? (specify, plan)
   NO  → Skip all references (read artifacts instead)

2. Is R in the manifest for feature F, artifact A?
   NO  → State = NEW → Load full

3. Has R been modified? (current checksum ≠ manifest checksum)
   YES → State = MODIFIED → Load full

4. Otherwise:
   State = INCORPORATED → Skip
```

---

## Script Implementation

### `check-references.sh` (Pre-Command)

```bash
#!/usr/bin/env bash
# Determines reference loading strategy
# Loads docs for specify and plan only; skips for other commands

set -e

TARGET_ARTIFACT=""
COMMAND=""
JSON_MODE=false
FEATURE_NAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --json) JSON_MODE=true; shift ;;
        --target) TARGET_ARTIFACT="$2"; shift 2 ;;
        --target=*) TARGET_ARTIFACT="${1#*=}"; shift ;;
        --command) COMMAND="$2"; shift 2 ;;
        --command=*) COMMAND="${1#*=}"; shift ;;
        --feature) FEATURE_NAME="$2"; shift 2 ;;
        --feature=*) FEATURE_NAME="${1#*=}"; shift ;;
        *) shift ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
eval $(get_feature_paths)

# ── Check if command needs reference loading ──

CONTEXT_COMMANDS="specify plan"
NEEDS_REFS=false
for cmd in $CONTEXT_COMMANDS; do
    [[ "$COMMAND" == "$cmd" ]] && NEEDS_REFS=true
done

if ! $NEEDS_REFS; then
    if $JSON_MODE; then
        echo '{"sprint":null,"load":[],"skip":[],"message":"Command does not load references"}'
    fi
    exit 0
fi

# ── Sprint detection ──

REFS_BASE="$REPO_ROOT/references"
CURRENT_SPRINT=""

[[ -z "$FEATURE_NAME" ]] && FEATURE_NAME="$CURRENT_BRANCH"

# Check for explicit override
if [[ -f "$REFS_BASE/.current-sprint" ]]; then
    CURRENT_SPRINT=$(cat "$REFS_BASE/.current-sprint" | tr -d '[:space:]')
fi

# Auto-detect if no override
if [[ -z "$CURRENT_SPRINT" ]]; then
    for dir in "$REFS_BASE"/sprint-*; do
        [[ -d "$dir" ]] || continue
        file_count=$(find "$dir" -maxdepth 1 -type f ! -name ".references-state.json" | wc -l)
        if [[ "$file_count" -gt 0 ]]; then
            CURRENT_SPRINT=$(basename "$dir")
        fi
    done
fi

# No sprint found
if [[ -z "$CURRENT_SPRINT" ]]; then
    if $JSON_MODE; then
        echo '{"sprint":null,"load":[],"skip":[],"message":"No sprint references found"}'
    fi
    exit 0
fi

REFS_DIR="$REFS_BASE/$CURRENT_SPRINT"
MANIFEST="$REFS_DIR/.references-state.json"

# Initialize empty manifest if missing
[[ -f "$MANIFEST" ]] || echo "{\"version\":1,\"sprint\":\"$CURRENT_SPRINT\",\"references\":{}}" > "$MANIFEST"

# Compute checksum
compute_checksum() {
    shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1
}

# Build loading plan
load_full=()
skip=()

for file in "$REFS_DIR"/*; do
    [[ -f "$file" ]] || continue
    [[ "$(basename "$file")" == ".references-state.json" ]] && continue

    filename=$(basename "$file")
    current_checksum=$(compute_checksum "$file")
    file_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file")

    # Check manifest state for this feature AND this artifact
    manifest_checksum=$(jq -r ".references[\"$filename\"].checksum // \"\"" "$MANIFEST")
    incorporated=$(jq -r ".references[\"$filename\"].incorporated_into[\"$FEATURE_NAME\"][\"$TARGET_ARTIFACT\"] // false" "$MANIFEST")

    if [[ -z "$manifest_checksum" ]]; then
        # NEW: not in manifest at all
        load_full+=("{\"file\":\"$filename\",\"path\":\"$file\",\"size\":$file_size,\"state\":\"NEW\"}")
    elif [[ "$current_checksum" != "$manifest_checksum" ]]; then
        # MODIFIED: checksum changed
        load_full+=("{\"file\":\"$filename\",\"path\":\"$file\",\"size\":$file_size,\"state\":\"MODIFIED\"}")
    elif [[ "$incorporated" == "true" ]]; then
        # INCORPORATED: already loaded for this artifact
        skip+=("$filename")
    else
        # Not yet incorporated into this artifact
        load_full+=("{\"file\":\"$filename\",\"path\":\"$file\",\"size\":$file_size,\"state\":\"NEW\"}")
    fi
done

# Output JSON
if $JSON_MODE; then
    cat <<EOF
{
  "sprint": "$CURRENT_SPRINT",
  "refs_dir": "$REFS_DIR",
  "feature": "$FEATURE_NAME",
  "command": "$COMMAND",
  "target": "$TARGET_ARTIFACT",
  "load": [$(IFS=,; echo "${load_full[*]}")],
  "skip": $(printf '%s\n' "${skip[@]}" | jq -R . | jq -s .)
}
EOF
fi
```

### `update-manifest.sh` (Post-Command)

```bash
#!/usr/bin/env bash
# Updates sprint manifest after command execution

set -e

REFS_DIR="$1"
FEATURE_NAME="$2"
TARGET_ARTIFACT="$3"

MANIFEST="$REFS_DIR/.references-state.json"

[[ -f "$MANIFEST" ]] || exit 0

# For each file in references, update manifest
for file in "$REFS_DIR"/*; do
    [[ -f "$file" ]] || continue
    [[ "$(basename "$file")" == ".references-state.json" ]] && continue

    filename=$(basename "$file")
    checksum=$(shasum -a 256 "$file" | cut -d' ' -f1)
    size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file")

    # Update manifest: mark as incorporated for this feature + artifact
    jq --arg f "$filename" \
       --arg c "$checksum" \
       --arg s "$size" \
       --arg feat "$FEATURE_NAME" \
       --arg art "$TARGET_ARTIFACT" \
       '.references[$f].checksum = $c |
        .references[$f].size_bytes = ($s | tonumber) |
        .references[$f].incorporated_into[$feat][$art] = true' \
       "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"
done
```

---

## Command Template Integration

```markdown
## Reference Loading Protocol

### Step 1: Check for References
Run `check-references.sh --json --command={command} --feature={feature} --target={artifact}`

If `sprint` is null or `load` is empty → proceed without references.

### Step 2: Process References

**load** array (NEW or MODIFIED):
- Read entire file content from the path provided
- These provide context for the current artifact

**skip** array (INCORPORATED):
- Do NOT read these files
- Already loaded for this artifact in a previous run

### Step 3: Generate Artifact
Use loaded references to inform your output.

### Step 4: Update Manifest
Run `update-manifest.sh {refs_dir} {feature} {artifact}`
```

---

## Simulation: Single Feature Workflow

### Setup

```
references/sprint-1/
├── prd.md (5000 bytes)
├── architecture.md (3000 bytes)
└── .references-state.json (empty)
```

### Feature 001-auth

| Command | Artifact | prd.md | architecture.md | Context |
|---------|----------|--------|-----------------|---------|
| specify | spec.md | NEW (5000) | NEW (3000) | 8000 |
| clarify | spec.md | — | — | 0 (reads spec.md) |
| plan | plan.md | NEW (5000) | NEW (3000) | 8000 |
| tasks | tasks.md | — | — | 0 (reads artifacts) |
| implement | code | — | — | 0 (reads tasks.md) |

**Total:** 16,000 bytes (2 context-gathering stages)
**Without smart loading:** 40,000 bytes (5 commands × 8000)
**Savings:** 60%

---

## Simulation: Multi-Feature Sprint

### Sprint 1

| Feature | Command | prd.md | architecture.md | Context |
|---------|---------|--------|-----------------|---------|
| 001-auth | specify | NEW | NEW | 8000 |
| 001-auth | plan | NEW | NEW | 8000 |
| 002-dashboard | specify | NEW | NEW | 8000 |
| 002-dashboard | plan | NEW | NEW | 8000 |

**Sprint 1 total:** 32,000 bytes
**Without smart loading:** 80,000 bytes
**Savings:** 60%

Each feature loads docs independently at specify and plan stages.

---

## Multi-Sprint Workflow

### Sprint 1: Initial Development

```
references/sprint-1/
├── prd.md (5000 bytes)
└── architecture.md (3000 bytes)
```

Features 001, 002 built.

### Sprint 2: No Docs Needed

No `references/sprint-2/` directory → normal speckit.

Feature 003 built without reference loading.

### Sprint 3: New Requirements

```
references/sprint-3/
└── security-req.md (4000 bytes)
```

Features 004, 005 built with new docs.

---

## Context Budget Summary

| Sprint | Features | Docs Size | Context Used | Without Smart | Savings |
|--------|----------|-----------|--------------|---------------|---------|
| 1 | 2 | 8KB | 32KB | 80KB | 60% |
| 2 | 1 | 0 | 0 | 0 | — |
| 3 | 2 | 4KB | 16KB | 40KB | 60% |
| **Total** | **5** | — | **48KB** | **120KB** | **60%** |

---

## User Workflows

### Workflow A: Sprint with Docs

```bash
# Start sprint 1 with design docs
mkdir -p references/sprint-1
cp ~/docs/prd.md references/sprint-1/
cp ~/docs/architecture.md references/sprint-1/

# Build features
/speckit.specify "Build auth"      # Loads docs for spec.md
/speckit.plan                      # Loads docs for plan.md
/speckit.tasks                     # Skips (reads spec.md + plan.md)
```

### Workflow B: Sprint without Docs

```bash
echo "sprint-2" > references/.current-sprint
/speckit.specify "Add logging"     # No refs, normal speckit
```

### Workflow C: New Sprint

```bash
mkdir -p references/sprint-3
cp ~/docs/security-req.md references/sprint-3/
/speckit.specify "Add security"    # Auto-detects sprint-3, loads docs
```

---

## User Escape Hatches

### Force Full Load
```bash
rm references/sprint-1/.references-state.json
```

### Switch Sprints
```bash
echo "sprint-1" > references/.current-sprint
```

### Inspect State
```bash
cat references/sprint-1/.references-state.json | jq .
```

### Debug Loading
```bash
./scripts/bash/check-references.sh --json --command=plan --feature=001-auth --target=plan.md
```

---

## Testing Strategy

### Unit Tests
- `test_command_classification.sh`: specify/plan load, others skip
- `test_sprint_detection.sh`: auto-detect vs override
- `test_per_artifact_tracking.sh`: same doc loads for spec.md AND plan.md

### Integration Tests
- Full feature workflow: specify → plan loads, tasks skips
- Multi-feature sprint: each feature loads independently
- Modified doc: re-loads for all subsequent artifacts

---

## Files to Create/Modify

| File | Change |
|------|--------|
| `scripts/bash/check-references.sh` | **NEW**: Command-aware state detection |
| `scripts/bash/update-manifest.sh` | **NEW**: Per-artifact manifest update |
| `scripts/bash/common.sh` | Add `REFS_BASE` to paths |
| `scripts/powershell/*` | PowerShell equivalents |
| `templates/commands/specify.md` | Add reference loading protocol |
| `templates/commands/plan.md` | Add reference loading protocol |

---

## Phased Implementation

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

Start with Phase 1. Add complexity only when users hit real problems.
