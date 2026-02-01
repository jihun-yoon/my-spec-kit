#!/usr/bin/env bash
# update-manifest.sh - Updates sprint manifest after command execution
#
# Marks all references in the sprint directory as incorporated for the
# specified feature and artifact.
#
# Usage:
#   ./update-manifest.sh <refs_dir> <feature_name> <target_artifact>
#   ./update-manifest.sh /path/to/references/sprint-1 001-auth spec.md
#
# This script:
#   1. Reads each reference file in the sprint directory
#   2. Computes its current checksum
#   3. Marks it as incorporated for the feature + artifact in the manifest

set -e

REFS_DIR="$1"
FEATURE_NAME="$2"
TARGET_ARTIFACT="$3"

# Validate arguments
if [[ -z "$REFS_DIR" ]] || [[ -z "$FEATURE_NAME" ]] || [[ -z "$TARGET_ARTIFACT" ]]; then
    echo "Usage: $0 <refs_dir> <feature_name> <target_artifact>" >&2
    echo "Example: $0 /path/to/references/sprint-1 001-auth spec.md" >&2
    exit 1
fi

# Check if refs directory exists
if [[ ! -d "$REFS_DIR" ]]; then
    echo "[refs] Warning: References directory does not exist: $REFS_DIR" >&2
    exit 0
fi

MANIFEST="$REFS_DIR/.references-state.json"

# Initialize manifest if it doesn't exist
if [[ ! -f "$MANIFEST" ]]; then
    sprint_name=$(basename "$REFS_DIR")
    echo "{\"version\":1,\"sprint\":\"$sprint_name\",\"references\":{}}" > "$MANIFEST"
fi

# ── Compute checksum for a file ──
compute_checksum() {
    if command -v shasum &>/dev/null; then
        shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1
    elif command -v sha256sum &>/dev/null; then
        sha256sum "$1" 2>/dev/null | cut -d' ' -f1
    else
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

# ── Update manifest for each reference file ──
updated_count=0

for file in "$REFS_DIR"/*; do
    [[ -f "$file" ]] || continue
    [[ "$(basename "$file")" == ".references-state.json" ]] && continue

    filename=$(basename "$file")
    checksum=$(compute_checksum "$file")
    size=$(get_file_size "$file")

    # Update manifest: mark as incorporated for this feature + artifact
    # Using jq to safely update nested JSON structure
    jq --arg f "$filename" \
       --arg c "$checksum" \
       --arg s "$size" \
       --arg feat "$FEATURE_NAME" \
       --arg art "$TARGET_ARTIFACT" \
       '
       # Ensure the reference entry exists with checksum and size
       .references[$f].checksum = $c |
       .references[$f].size_bytes = ($s | tonumber) |
       # Ensure incorporated_into structure exists
       .references[$f].incorporated_into //= {} |
       .references[$f].incorporated_into[$feat] //= {} |
       # Mark this artifact as incorporated
       .references[$f].incorporated_into[$feat][$art] = true
       ' "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"

    updated_count=$((updated_count + 1))
done

echo "[refs] Updated manifest: $updated_count references marked as incorporated into $FEATURE_NAME/$TARGET_ARTIFACT"
