# Smart Reference Loading: Design & Simulation

## Problem

Loading all reference documents every time wastes context tokens. We need the agent
to receive **only the right references** at each stage:

- **Already-incorporated refs** (same feature) should NOT be re-loaded
- **New refs** added after an artifact was created should be loaded in full
- **Modified refs** (content changed) should be re-loaded
- **Inherited refs** (from previous features) should be loaded fresh for each new feature

---

## Design Principles

1. **Script handles mechanics** — checksums, file detection are deterministic
2. **No summaries** — artifacts themselves are the synthesis of references
3. **Feature-scoped manifests** — each feature tracks its own incorporations
4. **Simple states** — only 3 states: NEW, MODIFIED, INCORPORATED

---

## Key Insight: Artifacts Are The Summaries

```
Workflow within a feature:
  prd.md ─────→ spec.md ─────→ plan.md ─────→ tasks.md
         reads          reads          reads

When plan.md runs:
  - It reads spec.md (which already synthesized prd.md)
  - spec.md contains the relevant extracted info
  - No need to summarize — the artifact IS the summary
```

This eliminates the need for AI-generated summaries entirely.

---

## Manifest Structure (`.references-state.json`)

### Schema (v1) — No Summaries

```json
{
  "version": 1,
  "references": {
    "prd.md": {
      "checksum": "sha256:a1b2c3d4e5f6...",
      "size_bytes": 4200,
      "incorporated_into": ["spec.md", "plan.md"]
    },
    "api-contract.yaml": {
      "checksum": "sha256:g7h8i9j0k1l2...",
      "size_bytes": 2100,
      "incorporated_into": ["spec.md"]
    }
  }
}
```

**What's tracked:**
- `checksum` — detect modifications
- `size_bytes` — logging/debugging
- `incorporated_into` — list of artifacts that consumed this reference

**What's NOT tracked:**
- Summaries (artifacts contain the synthesis)
- Timestamps (not needed for state detection)
- Cross-feature references (each feature has its own manifest)

---

## Reference States

Only 3 states needed:

| State | Condition | Action |
|-------|-----------|--------|
| `NEW` | Not in manifest | Load full |
| `MODIFIED` | Checksum changed | Load full |
| `INCORPORATED` | In manifest, unchanged | Skip |

### State Detection Logic

```
For each reference file R and target artifact A in current feature:

1. Is R in the manifest?
   NO  → State = NEW → Load full

2. Has R been modified? (current checksum ≠ manifest checksum)
   YES → State = MODIFIED → Load full

3. Otherwise:
   State = INCORPORATED → Skip (artifact chain has the synthesis)
```

---

## Cross-Feature Behavior

**Different features may need different parts of the same reference.**

| Scope | Behavior | Reason |
|-------|----------|--------|
| **Same feature** | Skip incorporated refs | Artifacts have synthesis |
| **New feature** | Load all refs fresh | May need different sections |

### Example: Large PRD Across Features

```
references/master-prd.md (10KB)
├── Section: Authentication
├── Section: Dashboard
├── Section: Billing

Feature 001-auth:
  master-prd.md → NEW → Load full
  spec.md extracts auth info
  plan.md → INCORPORATED → Skip (spec.md has auth synthesis)

Feature 002-dashboard (new feature, fresh manifest):
  master-prd.md → NEW → Load full (fresh manifest!)
  spec.md extracts dashboard info (different section)
  plan.md → INCORPORATED → Skip
```

Each feature pays the "load full" cost **once**, then skips for subsequent artifacts.

---

## Script Implementation

### `check-references.sh` (Pre-Command)

```bash
#!/usr/bin/env bash
# Determines reference loading strategy for a given target artifact
# Script handles ALL mechanical work - checksums, file detection, state computation

set -e

TARGET_ARTIFACT=""
JSON_MODE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --json) JSON_MODE=true; shift ;;
        --target) TARGET_ARTIFACT="$2"; shift 2 ;;
        --target=*) TARGET_ARTIFACT="${1#*=}"; shift ;;
        *) shift ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
eval $(get_feature_paths)

REFS_DIR="$FEATURE_DIR/references"
MANIFEST="$REFS_DIR/.references-state.json"

# Initialize empty manifest if missing
[[ -d "$REFS_DIR" ]] || mkdir -p "$REFS_DIR"
[[ -f "$MANIFEST" ]] || echo '{"version":1,"references":{}}' > "$MANIFEST"

# Compute checksum for a file
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

    if [[ -z "$manifest_checksum" ]]; then
        # NEW: not in manifest
        load_full+=("{\"file\":\"$filename\",\"size\":$file_size,\"state\":\"NEW\"}")
    elif [[ "$current_checksum" != "$manifest_checksum" ]]; then
        # MODIFIED: checksum changed
        load_full+=("{\"file\":\"$filename\",\"size\":$file_size,\"state\":\"MODIFIED\"}")
    else
        # INCORPORATED: already processed in this feature
        skip+=("$filename")
    fi
done

# Output JSON
if $JSON_MODE; then
    cat <<EOF
{
  "target": "$TARGET_ARTIFACT",
  "feature_dir": "$FEATURE_DIR",
  "refs_dir": "$REFS_DIR",
  "load": [$(IFS=,; echo "${load_full[*]}")],
  "skip": $(printf '%s\n' "${skip[@]}" | jq -R . | jq -s .)
}
EOF
fi
```

### `update-manifest.sh` (Post-Command)

```bash
#!/usr/bin/env bash
# Updates manifest after command execution
# No summaries - just records what was incorporated

set -e

REFS_DIR="$1"
TARGET_ARTIFACT="$2"

MANIFEST="$REFS_DIR/.references-state.json"

# For each file in references, update manifest
for file in "$REFS_DIR"/*; do
    [[ -f "$file" ]] || continue
    [[ "$(basename "$file")" == ".references-state.json" ]] && continue

    filename=$(basename "$file")
    checksum=$(shasum -a 256 "$file" | cut -d' ' -f1)
    size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file")

    # Update manifest entry - add target to incorporated_into array
    jq --arg f "$filename" \
       --arg c "$checksum" \
       --arg s "$size" \
       --arg t "$TARGET_ARTIFACT" \
       '.references[$f] = {
          checksum: $c,
          size_bytes: ($s | tonumber),
          incorporated_into: ((.references[$f].incorporated_into // []) + [$t] | unique)
        }' "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"
done
```

---

## Command Template Integration

Each command includes this reference loading protocol:

```markdown
## Reference Loading Protocol

### Step 1: Get Loading Plan
Run `check-references.sh --json --target={artifact}` and parse the output.

### Step 2: Process References

**load** array (NEW or MODIFIED):
- Read entire file content
- These provide new context for the current artifact

**skip** array (INCORPORATED):
- Do NOT read these files
- Their content is already synthesized in earlier artifacts
- Read those artifacts instead (spec.md, plan.md, etc.)

### Step 3: Generate Artifact
Use the loaded references + earlier artifacts to inform your output.

### Step 4: Update Manifest
Run `update-manifest.sh {refs_dir} {artifact}` to record incorporation.
```

---

## User Escape Hatches

### Force Full Load
```bash
# Delete manifest to treat all refs as NEW
rm specs/001-feature/references/.references-state.json
```

Next command will load all references fresh.

### Inspect State
```bash
# See what's been incorporated
cat specs/001-feature/references/.references-state.json | jq .
```

### Debug Loading Decisions
```bash
# Dry-run: see what would be loaded
./scripts/bash/check-references.sh --json --target=plan.md
```

---

## Simulation: Full Workflow

### Setup
```
specs/001-oauth-auth/
├── references/
│   ├── prd.md                    (4200 bytes)
│   ├── api-contract.yaml         (2100 bytes)
│   └── .references-state.json    (empty)
```

### Step 1: `/speckit.specify`

| Reference | State | Action |
|-----------|-------|--------|
| prd.md | NEW | Load full (4200 bytes) |
| api-contract.yaml | NEW | Load full (2100 bytes) |

**Context used: 6300 bytes**

After: manifest records both files incorporated into spec.md

### Step 2: `/speckit.plan`

| Reference | State | Action |
|-----------|-------|--------|
| prd.md | INCORPORATED | Skip |
| api-contract.yaml | INCORPORATED | Skip |

**Context used: 0 bytes** (reads spec.md instead, which has the synthesis)

### Step 3: User adds `security-req.md`

### Step 4: `/speckit.tasks`

| Reference | State | Action |
|-----------|-------|--------|
| prd.md | INCORPORATED | Skip |
| api-contract.yaml | INCORPORATED | Skip |
| security-req.md | NEW | Load full (3500 bytes) |

**Context used: 3500 bytes**

### Step 5: User modifies `prd.md`

### Step 6: `/speckit.implement`

| Reference | State | Action |
|-----------|-------|--------|
| prd.md | MODIFIED | Load full (4500 bytes) |
| api-contract.yaml | INCORPORATED | Skip |
| security-req.md | INCORPORATED | Skip |

**Context used: 4500 bytes**

---

## Context Budget Summary

| Command | Without Smart Loading | With Smart Loading | Savings |
|---------|----------------------|-------------------|---------|
| specify | 6,300 | 6,300 | 0% |
| plan | 6,300 | 0 | **100%** |
| tasks | 9,800 | 3,500 | **64%** |
| implement | 10,100 | 4,500 | **55%** |
| **Total** | **32,500** | **14,300** | **56%** |

---

## Cross-Feature Simulation

### Feature 001 Complete, Starting Feature 002

```
specs/001-auth/references/.references-state.json  ← has prd.md incorporated
specs/002-dashboard/references/                    ← empty, fresh manifest
```

### Feature 002: `/speckit.specify`

| Reference | Source | State | Action |
|-----------|--------|-------|--------|
| prd.md | copied to 002/references/ | NEW | Load full |

**Why load full?** Feature 002 has its own manifest. The same `prd.md` is NEW
to this feature because 002's manifest is empty. Dashboard feature may need
different sections of the PRD than auth feature did.

---

## Testing Strategy

### Unit Tests
- `test_state_detection.sh`: Given manifest + files, verify correct state
- `test_checksum_computation.sh`: Verify checksums are stable
- `test_manifest_update.sh`: Verify incorporated_into array updates correctly

### Integration Tests
- Full workflow with mock references → verify context savings
- Simulate file modifications → verify MODIFIED detection
- New feature with inherited files → verify fresh loading

### Property-Based Tests
- State machine transitions are deterministic
- Manifest incorporated_into is append-only within a feature
- Checksums always match file content

---

## Files to Create/Modify

| File | Change |
|------|--------|
| `scripts/bash/check-references.sh` | **NEW**: Pre-command state detection |
| `scripts/bash/update-manifest.sh` | **NEW**: Post-command manifest update |
| `scripts/bash/common.sh` | Add `REFERENCES_DIR` to paths |
| `scripts/bash/create-new-feature.sh` | Create `references/` directory |
| `scripts/powershell/*` | PowerShell equivalents |
| `templates/commands/*.md` | Add reference loading protocol |

---

## Phased Implementation

### Phase 1: MVP (Ship First)
- `check-references.sh` with state detection
- Basic manifest schema (v1, no summaries)
- Integration into `specify.md` and `plan.md` only

### Phase 2: Full Command Coverage
- Add to all commands
- `update-manifest.sh` for post-command updates
- `--force-load-refs` flag for escape hatch

### Phase 3: Cross-Feature Enhancement (If Needed)
- Project-level `references/` directory
- Three-source scanning (doc 09)
- Observability and metrics

Start with Phase 1. Add complexity only when users hit real problems.
