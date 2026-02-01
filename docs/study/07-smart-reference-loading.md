# Smart Reference Loading: Design & Simulation

## Problem

Loading all reference documents every time wastes context tokens. We need the agent
to receive **only the right references** at each stage:

- **Already-incorporated refs** should NOT be re-loaded in full
- **New refs** added after an artifact was created should be loaded in full
- **Modified refs** (content changed since incorporation) should be flagged and re-loaded

---

## Design Principles

1. **Script handles mechanics** — checksums, timestamps, file detection are deterministic
2. **AI handles semantics** — only the summary field requires AI intelligence
3. **Validation catches drift** — post-command validation ensures consistency
4. **Simple first** — start with minimal schema, add complexity only when needed

---

## Manifest Structure (`.references-state.json`)

### Simplified Schema (v1)

```json
{
  "version": 1,
  "references": {
    "prd.md": {
      "checksum": "sha256:a1b2c3d4e5f6...",
      "size_bytes": 4200,
      "incorporated_into": {
        "spec.md": {
          "checksum_at_incorporation": "sha256:a1b2c3d4e5f6...",
          "summary": ""
        }
      }
    }
  }
}
```

### Key Design Decision: Script-Writes, AI-Fills

**Problem with AI-written manifests:**
- AI can hallucinate checksums
- AI can forget to update the manifest
- AI output is non-deterministic
- Debugging "why did it load this?" is hard

**Solution: Invert ownership**

```
BEFORE (fragile):
  AI writes full JSON → Script validates afterward

AFTER (robust):
  Script writes JSON skeleton → AI fills ONLY summary field → Script finalizes
```

**Manifest Lifecycle:**

```
1. PRE-COMMAND: check-references.sh
   - Scans references/ directory
   - Computes checksums for all files
   - Reads existing manifest
   - Determines state (NEW/MODIFIED/INCORPORATED/SKIP)
   - Outputs loading plan as JSON

2. COMMAND EXECUTION: AI processes references
   - Receives loading plan
   - Reads files as instructed
   - Generates artifact
   - Produces summaries for each reference used

3. POST-COMMAND: update-manifest.sh
   - Receives summaries from AI (via structured output)
   - Writes mechanical fields (checksum, timestamp)
   - Inserts AI summaries into correct locations
   - Validates final manifest structure
```

This reduces AI's blast radius to **just the summary text**, which is the least critical field.

---

## Reference States

A reference can be in one of four states relative to a command:

| State | Meaning | What Agent Receives |
|-------|---------|---------------------|
| `NEW` | File not in manifest | Full content |
| `MODIFIED` | Checksum changed since last incorporation | Full content + previous summaries |
| `INCORPORATED_ELSEWHERE` | In manifest, used by other artifacts | Summary only |
| `ALREADY_INCORPORATED` | Already consumed by target artifact | Nothing (skip) |

### State Detection Logic

```
For each reference file R and target artifact A:

1. Is R in the manifest?
   NO  → State = NEW

2. Has R been modified? (current checksum ≠ manifest checksum)
   YES → State = MODIFIED

3. Has R been incorporated into artifact A?
   YES → State = ALREADY_INCORPORATED
   NO  → State = INCORPORATED_ELSEWHERE
```

---

## Script Implementation

### `check-references.sh` (Pre-Command)

```bash
#!/usr/bin/env bash
# Determines reference loading strategy for a given target artifact
# ALL mechanical work happens here - checksums, file detection, state computation

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
load_modified=()
summaries_only=()
skip=()

for file in "$REFS_DIR"/*; do
    [[ -f "$file" ]] || continue
    [[ "$(basename "$file")" == ".references-state.json" ]] && continue

    filename=$(basename "$file")
    current_checksum=$(compute_checksum "$file")

    # Check manifest state
    manifest_checksum=$(jq -r ".references[\"$filename\"].checksum // \"\"" "$MANIFEST")
    incorporated_into_target=$(jq -r ".references[\"$filename\"].incorporated_into[\"$TARGET_ARTIFACT\"] // null" "$MANIFEST")
    incorporated_anywhere=$(jq -r ".references[\"$filename\"].incorporated_into | length" "$MANIFEST")

    if [[ -z "$manifest_checksum" ]]; then
        # NEW: not in manifest
        load_full+=("$filename")
    elif [[ "$current_checksum" != "$manifest_checksum" ]]; then
        # MODIFIED: checksum changed
        load_modified+=("$filename")
    elif [[ "$incorporated_into_target" != "null" ]]; then
        # ALREADY_INCORPORATED: in target artifact
        skip+=("$filename")
    elif [[ "$incorporated_anywhere" -gt 0 ]]; then
        # INCORPORATED_ELSEWHERE: in other artifacts
        summaries_only+=("$filename")
    else
        # Fallback: treat as NEW
        load_full+=("$filename")
    fi
done

# Output JSON
if $JSON_MODE; then
    cat <<EOF
{
  "target": "$TARGET_ARTIFACT",
  "feature_dir": "$FEATURE_DIR",
  "load_full": $(printf '%s\n' "${load_full[@]}" | jq -R . | jq -s .),
  "load_modified": $(printf '%s\n' "${load_modified[@]}" | jq -R . | jq -s .),
  "summaries_only": $(printf '%s\n' "${summaries_only[@]}" | jq -R . | jq -s .),
  "skip": $(printf '%s\n' "${skip[@]}" | jq -R . | jq -s .)
}
EOF
fi
```

### `update-manifest.sh` (Post-Command)

```bash
#!/usr/bin/env bash
# Updates manifest with AI-provided summaries
# Script handles ALL mechanical fields; AI provides ONLY summaries

set -e

REFS_DIR="$1"
TARGET_ARTIFACT="$2"
SUMMARIES_JSON="$3"  # JSON object: {"prd.md": "summary text", ...}

MANIFEST="$REFS_DIR/.references-state.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# For each file that was processed, update manifest
for file in "$REFS_DIR"/*; do
    [[ -f "$file" ]] || continue
    [[ "$(basename "$file")" == ".references-state.json" ]] && continue

    filename=$(basename "$file")
    checksum=$(shasum -a 256 "$file" | cut -d' ' -f1)
    size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file")

    # Get summary from AI output (empty string if not provided)
    summary=$(echo "$SUMMARIES_JSON" | jq -r ".[\"$filename\"] // \"\"")

    # Update manifest entry
    jq --arg f "$filename" \
       --arg c "$checksum" \
       --arg s "$size" \
       --arg t "$TARGET_ARTIFACT" \
       --arg ts "$TIMESTAMP" \
       --arg sum "$summary" \
       '.references[$f] = {
          checksum: $c,
          size_bytes: ($s | tonumber),
          incorporated_into: ((.references[$f].incorporated_into // {}) + {
            ($t): {
              checksum_at_incorporation: $c,
              timestamp: $ts,
              summary: $sum
            }
          })
        }' "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"
done
```

---

## Command Template Integration

Each command includes this reference loading protocol:

```markdown
## Reference Loading Protocol

### Step 1: Get Loading Plan
Run `{SCRIPT_CHECK_REFS}` and parse the JSON output.

### Step 2: Process References by Category

**load_full** (NEW references):
- Read entire file content
- This is new context not yet incorporated anywhere

**load_modified** (MODIFIED references):
- Read entire file content
- ⚠️ Content changed since last incorporation
- Review what's new compared to previous summaries

**summaries_only** (INCORPORATED_ELSEWHERE):
- Do NOT read the file
- Use the summary from the manifest for context
- These were already synthesized into earlier artifacts

**skip** (ALREADY_INCORPORATED):
- Ignore entirely
- Already in the artifact you're generating

### Step 3: Generate Artifact
Use the loaded references to inform your output.

### Step 4: Provide Summaries
For each reference you processed (load_full or load_modified), provide a 1-2
sentence summary of what you extracted. Output as JSON:

```json
{
  "reference_summaries": {
    "prd.md": "Defines OAuth2 flow with Google/GitHub, 3 user roles, 3 journeys.",
    "security-req.md": "Requires OWASP top-10 compliance, rate limiting."
  }
}
```

The post-command script will update the manifest with your summaries.
```

---

## User Escape Hatches

### Force Full Load
```bash
# Ignore manifest, load all references fully
/speckit.plan --force-load-refs
```

Command template checks for this flag and loads everything as NEW.

### Clear Summaries
```bash
# Reset manifest to empty state
rm specs/001-feature/references/.references-state.json
```

Next command will treat all refs as NEW.

### Inspect State
```bash
# See what the AI "knows" about each reference
cat specs/001-feature/references/.references-state.json | jq '.references | to_entries[] | {file: .key, summaries: .value.incorporated_into}'
```

### Debug Loading Decisions
```bash
# Dry-run: see what would be loaded without running command
./scripts/bash/check-references.sh --json --target=plan.md | jq .
```

---

## Observability

### Logging
Each command logs reference loading decisions:

```
[refs] Loading plan for target: plan.md
[refs]   NEW: security-requirements.md (3500 bytes)
[refs]   MODIFIED: prd.md (4200 bytes, was a1b2c3, now p6q7r8)
[refs]   SUMMARY: api-contract.yaml → "4 auth endpoints: login, register, me, refresh."
[refs]   SKIP: (none)
[refs] Total context: 7700 bytes (saved 2400 bytes vs full load)
```

### Metrics (Future)
Track across sessions:
- Total bytes saved by smart loading
- Summary hit rate (how often summaries are sufficient)
- Modification frequency (how often refs change mid-feature)

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

After: manifest updated with checksums + AI summaries for spec.md

### Step 2: `/speckit.clarify`

| Reference | State | Action |
|-----------|-------|--------|
| prd.md | ALREADY_INCORPORATED | Skip |
| api-contract.yaml | ALREADY_INCORPORATED | Skip |

**Context used: 0 bytes** (100% savings)

### Step 3: User adds `security-req.md`

### Step 4: `/speckit.plan`

| Reference | State | Action |
|-----------|-------|--------|
| prd.md | INCORPORATED_ELSEWHERE | Summary only (~80 bytes) |
| api-contract.yaml | INCORPORATED_ELSEWHERE | Summary only (~60 bytes) |
| security-req.md | NEW | Load full (3500 bytes) |

**Context used: 3640 bytes** (63% savings vs 9800)

### Step 5: User modifies `prd.md`

### Step 6: `/speckit.tasks`

| Reference | State | Action |
|-----------|-------|--------|
| prd.md | MODIFIED | Load full + flag (4500 bytes) |
| api-contract.yaml | INCORPORATED_ELSEWHERE | Summary only |
| security-req.md | INCORPORATED_ELSEWHERE | Summary only |

**Context used: 4640 bytes** (54% savings)

---

## Context Budget Summary

| Command | Without Smart Loading | With Smart Loading | Savings |
|---------|----------------------|-------------------|---------|
| specify | 6,300 | 6,300 | 0% |
| clarify | 6,300 | 0 | **100%** |
| plan | 9,800 | 3,640 | **63%** |
| tasks | 10,100 | 4,640 | **54%** |
| implement | 10,100 | 140 | **99%** |
| **Total** | **42,600** | **14,720** | **65%** |

---

## Testing Strategy

### Unit Tests
- `test_state_detection.sh`: Given manifest + files, verify correct state assignment
- `test_checksum_computation.sh`: Verify checksums are stable and correct
- `test_manifest_update.sh`: Verify script correctly updates manifest structure

### Integration Tests
- Full workflow with mock references → verify context savings
- Simulate file modifications → verify MODIFIED detection
- Simulate file deletions → verify stale entry handling

### Property-Based Tests
- State machine transitions are deterministic
- Manifest never loses data (append-only for incorporated_into)
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
- Basic manifest schema (v1)
- Integration into `specify.md` and `plan.md` only
- No cross-feature scanning

### Phase 2: Full Command Coverage
- Add to all commands
- `update-manifest.sh` for post-command updates
- Validation script

### Phase 3: Cross-Feature (If Needed)
- Scan previous features' references (doc 09)
- Add `--force-load-refs` escape hatch
- Observability and metrics

Start with Phase 1. Add complexity only when users hit real problems.
