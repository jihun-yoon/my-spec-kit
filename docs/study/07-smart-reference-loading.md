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
5. **Shared context** — features in same sprint share incorporation state

---

## Key Insight: Artifacts Are The Summaries

```
Workflow within a sprint:
  prd.md ─────→ spec.md ─────→ plan.md ─────→ tasks.md
         reads          reads          reads

When plan.md runs:
  - It reads spec.md (which already synthesized prd.md)
  - spec.md contains the relevant extracted info
  - No need to summarize — the artifact IS the summary
```

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
│   │   ├── system-design.md
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
    ├── 001-auth/                 ← Sprint 1 feature
    ├── 002-dashboard/            ← Sprint 1 feature
    ├── 003-profile/              ← Sprint 2 feature (no docs)
    ├── 004-billing/              ← Sprint 3 feature
    └── 005-notifications/        ← Sprint 3 feature
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

**Auto-detect example:**
```
references/
├── sprint-1/    (has files)
├── sprint-2/    (empty)
└── sprint-3/    (has files)

→ Auto-selects sprint-3 (highest with files)
```

**Override example:**
```bash
echo "sprint-1" > references/.current-sprint
→ Uses sprint-1 even though sprint-3 exists
```

---

## Manifest Structure (`.references-state.json`)

### Sprint-Scoped Manifest

Each sprint has its own manifest tracking ALL features in that sprint:

```json
{
  "version": 1,
  "sprint": "sprint-1",
  "references": {
    "prd.md": {
      "checksum": "sha256:a1b2c3d4e5f6...",
      "size_bytes": 4200,
      "incorporated_into": {
        "001-auth": ["spec.md", "plan.md"],
        "002-dashboard": ["spec.md"]
      }
    },
    "system-design.md": {
      "checksum": "sha256:x7y8z9...",
      "size_bytes": 3100,
      "incorporated_into": {
        "001-auth": ["plan.md"]
      }
    }
  }
}
```

**What's tracked:**
- `checksum` — detect modifications
- `size_bytes` — logging/debugging
- `incorporated_into` — map of feature → artifacts that consumed this ref

---

## Reference States

Only 3 states:

| State | Condition | Action |
|-------|-----------|--------|
| `NEW` | Not in manifest | Load full |
| `MODIFIED` | Checksum changed | Load full |
| `INCORPORATED` | In manifest for this feature, unchanged | Skip |

### State Detection Logic

```
For reference R, feature F, artifact A in current sprint:

1. Is R in the manifest?
   NO  → State = NEW → Load full

2. Has R been modified? (current checksum ≠ manifest checksum)
   YES → State = MODIFIED → Load full

3. Was R incorporated into THIS feature (F)?
   YES → State = INCORPORATED → Skip

4. Was R incorporated into ANOTHER feature in same sprint?
   YES → State = INCORPORATED → Skip (sprint features share context)
```

**Key:** Features within the same sprint share incorporation state.

---

## Script Implementation

### `check-references.sh` (Pre-Command)

```bash
#!/usr/bin/env bash
# Determines reference loading strategy
# Supports sprint-based organization with auto-detection

set -e

TARGET_ARTIFACT=""
JSON_MODE=false
FEATURE_NAME=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --json) JSON_MODE=true; shift ;;
        --target) TARGET_ARTIFACT="$2"; shift 2 ;;
        --target=*) TARGET_ARTIFACT="${1#*=}"; shift ;;
        --feature) FEATURE_NAME="$2"; shift 2 ;;
        --feature=*) FEATURE_NAME="${1#*=}"; shift ;;
        *) shift ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
eval $(get_feature_paths)

REFS_BASE="$REPO_ROOT/references"
CURRENT_SPRINT=""
REFS_DIR=""

# Auto-detect feature name from branch if not provided
[[ -z "$FEATURE_NAME" ]] && FEATURE_NAME="$CURRENT_BRANCH"

# ── Determine current sprint ──

# Check for explicit override
if [[ -f "$REFS_BASE/.current-sprint" ]]; then
    CURRENT_SPRINT=$(cat "$REFS_BASE/.current-sprint" | tr -d '[:space:]')
fi

# Auto-detect if no override
if [[ -z "$CURRENT_SPRINT" ]]; then
    # Find highest numbered sprint directory with files
    for dir in "$REFS_BASE"/sprint-*; do
        [[ -d "$dir" ]] || continue
        # Check if directory has files (excluding manifest)
        file_count=$(find "$dir" -maxdepth 1 -type f ! -name ".references-state.json" | wc -l)
        if [[ "$file_count" -gt 0 ]]; then
            CURRENT_SPRINT=$(basename "$dir")
        fi
    done
fi

# ── No sprint found → no reference loading ──

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

    # Check manifest state
    manifest_checksum=$(jq -r ".references[\"$filename\"].checksum // \"\"" "$MANIFEST")
    incorporated=$(jq -r ".references[\"$filename\"].incorporated_into | keys | length" "$MANIFEST")

    if [[ -z "$manifest_checksum" ]]; then
        # NEW: not in manifest
        load_full+=("{\"file\":\"$filename\",\"path\":\"$file\",\"size\":$file_size,\"state\":\"NEW\"}")
    elif [[ "$current_checksum" != "$manifest_checksum" ]]; then
        # MODIFIED: checksum changed
        load_full+=("{\"file\":\"$filename\",\"path\":\"$file\",\"size\":$file_size,\"state\":\"MODIFIED\"}")
    elif [[ "$incorporated" -gt 0 ]]; then
        # INCORPORATED: already processed in this sprint
        skip+=("$filename")
    else
        # Fallback: treat as NEW
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

    # Update manifest: add artifact to feature's incorporated list
    jq --arg f "$filename" \
       --arg c "$checksum" \
       --arg s "$size" \
       --arg feat "$FEATURE_NAME" \
       --arg art "$TARGET_ARTIFACT" \
       '.references[$f].checksum = $c |
        .references[$f].size_bytes = ($s | tonumber) |
        .references[$f].incorporated_into[$feat] = ((.references[$f].incorporated_into[$feat] // []) + [$art] | unique)' \
       "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"
done
```

---

## Command Template Integration

```markdown
## Reference Loading Protocol

### Step 1: Check for References
Run `check-references.sh --json --feature={feature} --target={artifact}`

If `sprint` is null → no references, proceed with normal speckit workflow.

### Step 2: Process References

**load** array (NEW or MODIFIED):
- Read entire file content from the path provided
- These provide new context for the current artifact

**skip** array (INCORPORATED):
- Do NOT read these files
- Already synthesized into earlier artifacts in this sprint
- Read those artifacts for context instead

### Step 3: Generate Artifact
Use loaded references + earlier artifacts to inform your output.

### Step 4: Update Manifest
Run `update-manifest.sh {refs_dir} {feature} {artifact}`
```

---

## User Workflows

### Workflow A: Sprint with Docs

```bash
# Start sprint 1 with design docs
mkdir -p references/sprint-1
cp ~/docs/prd.md references/sprint-1/
cp ~/docs/architecture.md references/sprint-1/

# Build features (docs auto-loaded)
/speckit.specify "Build auth system"      # 001-auth, loads both docs
/speckit.specify "Build dashboard"        # 002-dashboard, skips (incorporated)
```

### Workflow B: Sprint without Docs

```bash
# Sprint 2: no docs needed
echo "sprint-2" > references/.current-sprint
# Or just don't create sprint-2/ directory

/speckit.specify "Add logging"            # Normal speckit, no refs
/speckit.specify "Add monitoring"         # Normal speckit, no refs
```

### Workflow C: New Sprint with New Docs

```bash
# Sprint 3: new requirements
mkdir -p references/sprint-3
cp ~/docs/security-requirements.md references/sprint-3/

# Auto-detects sprint-3 (highest with files)
/speckit.specify "Add security layer"     # 004-security, loads new doc
```

### Workflow D: Override Sprint

```bash
# Force use of sprint-1 docs for a new feature
echo "sprint-1" > references/.current-sprint
/speckit.specify "Revisit auth"           # Uses sprint-1 docs
```

---

## Simulation: Multi-Sprint Workflow

### Sprint 1: Initial Development

```
references/sprint-1/
├── prd.md (5000 bytes)
├── architecture.md (3000 bytes)
└── .references-state.json (empty)
```

| Command | Feature | Reference | State | Context |
|---------|---------|-----------|-------|---------|
| specify | 001-auth | prd.md | NEW | 5000 |
| specify | 001-auth | architecture.md | NEW | 3000 |
| plan | 001-auth | both | INCORPORATED | 0 |
| specify | 002-dashboard | both | INCORPORATED | 0 |

**Sprint 1 total: 8000 bytes** (loaded once, shared across features)

### Sprint 2: No Docs

```
references/sprint-2/ (doesn't exist)
```

| Command | Feature | Reference | State | Context |
|---------|---------|-----------|-------|---------|
| specify | 003-profile | (none) | — | 0 |
| plan | 003-profile | (none) | — | 0 |

**Sprint 2 total: 0 bytes** (no reference loading)

### Sprint 3: New Requirements

```
references/sprint-3/
├── security-req.md (4000 bytes)
└── .references-state.json (empty)
```

| Command | Feature | Reference | State | Context |
|---------|---------|-----------|-------|---------|
| specify | 004-security | security-req.md | NEW | 4000 |
| specify | 005-compliance | security-req.md | INCORPORATED | 0 |

**Sprint 3 total: 4000 bytes** (loaded once)

---

## Context Budget Summary

| Sprint | Features | Docs | Without Smart Loading | With Smart Loading | Savings |
|--------|----------|------|----------------------|-------------------|---------|
| 1 | 2 | 2 | 16,000 | 8,000 | **50%** |
| 2 | 1 | 0 | 0 | 0 | — |
| 3 | 2 | 1 | 8,000 | 4,000 | **50%** |
| **Total** | **5** | **3** | **24,000** | **12,000** | **50%** |

---

## User Escape Hatches

### Force Full Load
```bash
# Delete sprint manifest to treat all refs as NEW
rm references/sprint-1/.references-state.json
```

### Switch Sprints
```bash
# Explicitly set current sprint
echo "sprint-1" > references/.current-sprint
```

### Inspect State
```bash
# See what's been incorporated
cat references/sprint-1/.references-state.json | jq .
```

### Debug Loading
```bash
# Dry-run: see what would be loaded
./scripts/bash/check-references.sh --json --feature=001-auth --target=spec.md
```

### Archive Old Docs
```bash
# Move to _archive/ (ignored by script)
mv references/sprint-1/old-doc.md references/_archive/
```

---

## Testing Strategy

### Unit Tests
- `test_sprint_detection.sh`: Auto-detect vs explicit override
- `test_state_detection.sh`: NEW/MODIFIED/INCORPORATED states
- `test_no_refs.sh`: Graceful handling when no references exist

### Integration Tests
- Multi-sprint workflow with shared docs
- Sprint without docs → normal speckit behavior
- Feature in sprint shares incorporation with other features

### Edge Cases
- Empty sprint directory → no loading
- Missing `.current-sprint` with multiple sprint dirs → use highest
- Manifest exists but reference file deleted → handle gracefully

---

## Files to Create/Modify

| File | Change |
|------|--------|
| `scripts/bash/check-references.sh` | **NEW**: Sprint-aware state detection |
| `scripts/bash/update-manifest.sh` | **NEW**: Sprint manifest update |
| `scripts/bash/common.sh` | Add `REFS_BASE` to paths |
| `scripts/powershell/*` | PowerShell equivalents |
| `templates/commands/*.md` | Add reference loading protocol |

---

## Phased Implementation

### Phase 1: MVP (Ship First)
- `check-references.sh` with sprint detection
- Basic manifest schema (v1, no summaries)
- Integration into `specify.md` and `plan.md` only
- Auto-detect current sprint

### Phase 2: Full Command Coverage
- Add to all commands
- `update-manifest.sh` for manifest updates
- `--refs` filter flag for power users

### Phase 3: Enhancements (If Needed)
- Observability and metrics
- Sprint history/comparison tools
- Cross-sprint reference inheritance

Start with Phase 1. Add complexity only when users hit real problems.
