#!/usr/bin/env bash
# check-references.sh - Determines reference loading strategy
#
# Loads docs for 'specify' and 'plan' commands only; skips for others.
# Supports sprint-based organization with auto-detection.
#
# Usage:
#   ./check-references.sh --json --command=specify --feature=001-auth --target=spec.md
#
# Output (JSON):
#   {
#     "sprint": "sprint-1",
#     "refs_dir": "/path/to/references/sprint-1",
#     "feature": "001-auth",
#     "command": "specify",
#     "target": "spec.md",
#     "load": [{"file": "prd.md", "path": "/full/path", "size": 5000, "state": "NEW"}],
#     "skip": ["already-loaded.md"]
#   }

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
        --help|-h)
            echo "Usage: $0 [--json] --command=<cmd> --feature=<name> --target=<artifact>"
            echo ""
            echo "Options:"
            echo "  --json              Output in JSON format"
            echo "  --command <cmd>     Command name (specify, plan, tasks, etc.)"
            echo "  --feature <name>    Feature name (e.g., 001-auth)"
            echo "  --target <artifact> Target artifact (e.g., spec.md, plan.md)"
            exit 0
            ;;
        *) shift ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"
eval $(get_feature_paths)

# ── Check if command needs reference loading ──
# Only 'specify' and 'plan' are context-gathering commands

CONTEXT_COMMANDS="specify plan"
NEEDS_REFS=false
for cmd in $CONTEXT_COMMANDS; do
    [[ "$COMMAND" == "$cmd" ]] && NEEDS_REFS=true
done

if ! $NEEDS_REFS; then
    if $JSON_MODE; then
        cat <<EOF
{
  "sprint": null,
  "refs_dir": null,
  "feature": "$FEATURE_NAME",
  "command": "$COMMAND",
  "target": "$TARGET_ARTIFACT",
  "load": [],
  "skip": [],
  "message": "Command '$COMMAND' does not load references (only specify/plan do)"
}
EOF
    else
        echo "[refs] Command '$COMMAND' does not load references"
    fi
    exit 0
fi

# ── Sprint detection ──

REFS_BASE="$REPO_ROOT/references"
CURRENT_SPRINT=""

# Auto-detect feature name from branch if not provided
[[ -z "$FEATURE_NAME" ]] && FEATURE_NAME="$CURRENT_BRANCH"

# Check for explicit override in .current-sprint file
if [[ -f "$REFS_BASE/.current-sprint" ]]; then
    CURRENT_SPRINT=$(cat "$REFS_BASE/.current-sprint" | tr -d '[:space:]')
fi

# Auto-detect if no override: find highest numbered sprint directory with files
if [[ -z "$CURRENT_SPRINT" ]]; then
    if [[ -d "$REFS_BASE" ]]; then
        for dir in "$REFS_BASE"/sprint-*; do
            [[ -d "$dir" ]] || continue
            # Check if directory has files (excluding manifest)
            file_count=$(find "$dir" -maxdepth 1 -type f ! -name ".references-state.json" 2>/dev/null | wc -l | tr -d ' ')
            if [[ "$file_count" -gt 0 ]]; then
                CURRENT_SPRINT=$(basename "$dir")
            fi
        done
    fi
fi

# ── No sprint found → no reference loading ──

if [[ -z "$CURRENT_SPRINT" ]]; then
    if $JSON_MODE; then
        cat <<EOF
{
  "sprint": null,
  "refs_dir": null,
  "feature": "$FEATURE_NAME",
  "command": "$COMMAND",
  "target": "$TARGET_ARTIFACT",
  "load": [],
  "skip": [],
  "message": "No sprint references found"
}
EOF
    else
        echo "[refs] No sprint references found"
    fi
    exit 0
fi

REFS_DIR="$REFS_BASE/$CURRENT_SPRINT"
MANIFEST="$REFS_DIR/.references-state.json"

# Initialize empty manifest if missing
if [[ ! -f "$MANIFEST" ]]; then
    echo "{\"version\":1,\"sprint\":\"$CURRENT_SPRINT\",\"references\":{}}" > "$MANIFEST"
fi

# ── Compute checksum for a file ──
compute_checksum() {
    if command -v shasum &>/dev/null; then
        shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1
    elif command -v sha256sum &>/dev/null; then
        sha256sum "$1" 2>/dev/null | cut -d' ' -f1
    else
        # Fallback: use md5 if available
        md5 -q "$1" 2>/dev/null || md5sum "$1" 2>/dev/null | cut -d' ' -f1
    fi
}

# ── Get file size ──
get_file_size() {
    if stat -f%z "$1" &>/dev/null; then
        stat -f%z "$1"
    else
        stat -c%s "$1" 2>/dev/null || echo "0"
    fi
}

# ── Build loading plan ──
load_full=()
skip=()

for file in "$REFS_DIR"/*; do
    [[ -f "$file" ]] || continue
    [[ "$(basename "$file")" == ".references-state.json" ]] && continue

    filename=$(basename "$file")
    current_checksum=$(compute_checksum "$file")
    file_size=$(get_file_size "$file")

    # Check manifest state for this feature AND this artifact
    manifest_checksum=$(jq -r ".references[\"$filename\"].checksum // \"\"" "$MANIFEST" 2>/dev/null || echo "")
    incorporated=$(jq -r ".references[\"$filename\"].incorporated_into[\"$FEATURE_NAME\"][\"$TARGET_ARTIFACT\"] // false" "$MANIFEST" 2>/dev/null || echo "false")

    if [[ -z "$manifest_checksum" ]]; then
        # NEW: not in manifest at all
        load_full+=("{\"file\":\"$filename\",\"path\":\"$file\",\"size\":$file_size,\"state\":\"NEW\"}")
    elif [[ "$current_checksum" != "$manifest_checksum" ]]; then
        # MODIFIED: checksum changed since last load
        load_full+=("{\"file\":\"$filename\",\"path\":\"$file\",\"size\":$file_size,\"state\":\"MODIFIED\"}")
    elif [[ "$incorporated" == "true" ]]; then
        # INCORPORATED: already loaded for this artifact
        skip+=("$filename")
    else
        # Not yet incorporated into this artifact (but exists in manifest for other features/artifacts)
        load_full+=("{\"file\":\"$filename\",\"path\":\"$file\",\"size\":$file_size,\"state\":\"NEW\"}")
    fi
done

# ── Output ──

if $JSON_MODE; then
    # Build JSON arrays
    load_json="["
    first=true
    for item in "${load_full[@]}"; do
        if $first; then
            first=false
        else
            load_json+=","
        fi
        load_json+="$item"
    done
    load_json+="]"

    skip_json="["
    first=true
    for item in "${skip[@]}"; do
        if $first; then
            first=false
        else
            skip_json+=","
        fi
        skip_json+="\"$item\""
    done
    skip_json+="]"

    cat <<EOF
{
  "sprint": "$CURRENT_SPRINT",
  "refs_dir": "$REFS_DIR",
  "feature": "$FEATURE_NAME",
  "command": "$COMMAND",
  "target": "$TARGET_ARTIFACT",
  "load": $load_json,
  "skip": $skip_json
}
EOF
else
    echo "[refs] Sprint: $CURRENT_SPRINT"
    echo "[refs] Feature: $FEATURE_NAME"
    echo "[refs] Target: $TARGET_ARTIFACT"
    echo "[refs] To load:"
    for item in "${load_full[@]}"; do
        echo "  - $item"
    done
    echo "[refs] To skip:"
    for item in "${skip[@]}"; do
        echo "  - $item"
    done
fi
