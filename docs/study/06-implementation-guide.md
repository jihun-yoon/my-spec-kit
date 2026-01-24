# Implementation Guide: Reference Document Feature

## Problem Statement

The current Spec-Kit system loses context because:
1. All new context comes from user chat input (`$ARGUMENTS`) only
2. Commands don't load external reference documents
3. Large PRDs or design docs can't be referenced directly
4. Scripts return available docs but commands don't synthesize them into context

## Proposed Solution

Add a `references/` directory that commands can detect, load, and synthesize into generated artifacts.

---

## Implementation Phases

### Phase 1: Script Changes

#### 1.1 Modify `scripts/bash/common.sh`

Add new function to detect reference documents:

```bash
# Add after get_feature_paths()

# Find reference documents in the feature directory
find_reference_docs() {
    local feature_dir="$1"
    local refs_dir="$feature_dir/references"
    local refs=()

    if [[ -d "$refs_dir" ]]; then
        for file in "$refs_dir"/*; do
            if [[ -f "$file" ]]; then
                refs+=("$(basename "$file")")
            fi
        done
    fi

    # Output as space-separated list
    echo "${refs[*]}"
}

# Get reference docs as JSON array
get_reference_docs_json() {
    local feature_dir="$1"
    local refs_dir="$feature_dir/references"

    if [[ ! -d "$refs_dir" ]] || [[ -z "$(ls -A "$refs_dir" 2>/dev/null)" ]]; then
        echo "[]"
        return
    fi

    local json_refs=""
    for file in "$refs_dir"/*; do
        if [[ -f "$file" ]]; then
            if [[ -n "$json_refs" ]]; then
                json_refs="$json_refs,"
            fi
            json_refs="$json_refs\"$(basename "$file")\""
        fi
    done

    echo "[$json_refs]"
}
```

Update `get_feature_paths()` to include references:

```bash
get_feature_paths() {
    local repo_root=$(get_repo_root)
    local current_branch=$(get_current_branch)
    local has_git_repo="false"

    if has_git; then
        has_git_repo="true"
    fi

    local feature_dir=$(find_feature_dir_by_prefix "$repo_root" "$current_branch")

    cat <<EOF
REPO_ROOT='$repo_root'
CURRENT_BRANCH='$current_branch'
HAS_GIT='$has_git_repo'
FEATURE_DIR='$feature_dir'
FEATURE_SPEC='$feature_dir/spec.md'
IMPL_PLAN='$feature_dir/plan.md'
TASKS='$feature_dir/tasks.md'
RESEARCH='$feature_dir/research.md'
DATA_MODEL='$feature_dir/data-model.md'
QUICKSTART='$feature_dir/quickstart.md'
CONTRACTS_DIR='$feature_dir/contracts'
REFERENCES_DIR='$feature_dir/references'
EOF
}
```

#### 1.2 Modify `scripts/bash/check-prerequisites.sh`

Add reference docs to the AVAILABLE_DOCS output:

```bash
# After line 134 (checking quickstart), add:

# Check references directory
if [[ -d "$FEATURE_DIR/references" ]] && [[ -n "$(ls -A "$FEATURE_DIR/references" 2>/dev/null)" ]]; then
    docs+=("references/")
fi
```

Update JSON output to include reference docs:

```bash
# Replace the JSON output section with:
if $JSON_MODE; then
    # Build JSON array of documents
    if [[ ${#docs[@]} -eq 0 ]]; then
        json_docs="[]"
    else
        json_docs=$(printf '"%s",' "${docs[@]}")
        json_docs="[${json_docs%,}]"
    fi

    # Get reference docs
    ref_docs=$(get_reference_docs_json "$FEATURE_DIR")

    printf '{"FEATURE_DIR":"%s","AVAILABLE_DOCS":%s,"REFERENCE_DOCS":%s}\n' \
        "$FEATURE_DIR" "$json_docs" "$ref_docs"
fi
```

#### 1.3 Modify `scripts/bash/create-new-feature.sh`

Create references directory when creating feature:

```bash
# After line 281: mkdir -p "$FEATURE_DIR"
# Add:
mkdir -p "$FEATURE_DIR/references"
```

Update JSON output to include references path:

```bash
# Update line 291:
printf '{"BRANCH_NAME":"%s","SPEC_FILE":"%s","FEATURE_NUM":"%s","REFERENCES_DIR":"%s"}\n' \
    "$BRANCH_NAME" "$SPEC_FILE" "$FEATURE_NUM" "$FEATURE_DIR/references"
```

---

### Phase 2: Template Changes

#### 2.1 Modify `templates/spec-template.md`

Add reference documents section:

```markdown
# Feature Specification: [FEATURE NAME]

**Feature Branch**: `[###-feature-name]`
**Created**: [DATE]
**Status**: Draft
**Input**: User description: "$ARGUMENTS"

## Reference Documents *(if available)*

<!--
  If external reference documents are provided in the references/ directory,
  list them here and summarize key points that inform this specification.
-->

### Provided References

- [List each file in references/ directory]

### Key Points from References

- [Summarize critical requirements, constraints, or context from reference docs]
- [Note any conflicts or ambiguities between reference docs]

---

## User Scenarios & Testing *(mandatory)*
...
```

#### 2.2 Modify `templates/plan-template.md`

Add section to acknowledge reference documents:

```markdown
## Reference Document Analysis *(if applicable)*

<!--
  If reference documents were provided, analyze them for:
  - Technical constraints or requirements
  - Existing patterns or conventions to follow
  - Integration points with existing systems
-->

### Documents Reviewed

| Document | Purpose | Key Takeaways |
|----------|---------|---------------|
| [file.md] | [What it describes] | [Critical points for implementation] |

### Impact on Technical Decisions

[How reference documents influence architecture, tech stack, or approach]
```

---

### Phase 3: Command Changes

#### 3.1 Modify `templates/commands/specify.md`

Add step to load reference documents:

```markdown
## Outline

...

2.5. **Load reference documents** (if any exist):
   - Check if `FEATURE_DIR/references/` directory exists and contains files
   - For each file in references/:
     - Read the file content
     - Extract key requirements, constraints, and context
     - Note any conflicts or ambiguities between documents
   - Synthesize findings into the specification
   - Document which reference docs were used and key takeaways

3. Load `templates/spec-template.md` to understand required sections.

4. Follow this execution flow:

    1. Parse user description from Input
       If empty: ERROR "No feature description provided"
    2. **Load and analyze reference documents** (NEW)
       - Read all files in references/ directory
       - Extract: requirements, constraints, user stories, acceptance criteria
       - Note: terminology, domain concepts, existing patterns
    3. Extract key concepts from description AND reference docs
       Identify: actors, actions, data, constraints
    ...
```

#### 3.2 Modify `templates/commands/plan.md`

Add reference document loading:

```markdown
## Outline

1. **Setup**: Run `{SCRIPT}` from repo root and parse JSON for FEATURE_SPEC, IMPL_PLAN, SPECS_DIR, BRANCH, REFERENCE_DOCS.

2. **Load context**:
   - Read FEATURE_SPEC and `/memory/constitution.md`
   - Load IMPL_PLAN template (already copied)
   - **Load all files in references/ directory** (NEW)
     - For each reference doc, extract technical requirements and constraints
     - Note any architecture patterns, API contracts, or integration specs

3. **Execute plan workflow**: Follow the structure in IMPL_PLAN template to:
   - Fill Technical Context (incorporate constraints from reference docs)
   ...
```

#### 3.3 Modify `templates/commands/clarify.md`

Reference docs when answering clarifying questions:

```markdown
## Outline

...

2. **Load context for clarification**:
   - Read FEATURE_SPEC
   - **Read all files in references/ directory** (NEW)
   - Cross-reference spec gaps against reference documents
   - Some clarifications may be answered by reference docs

3. **Scan for coverage gaps** using this taxonomy:
   ...
   - Before marking [NEEDS CLARIFICATION], check if answer exists in reference docs
```

#### 3.4 Modify `templates/commands/tasks.md`

Include references for context:

```markdown
## Outline

1. **Setup**: Run `{SCRIPT}` and parse JSON for FEATURE_DIR, AVAILABLE_DOCS, REFERENCE_DOCS.

2. **Load context**:
   - Read plan.md (required)
   - Read optional docs from AVAILABLE_DOCS
   - **Read reference docs** to understand original requirements context
   ...
```

---

### Phase 4: PowerShell Equivalents

Create PowerShell versions of all bash changes:

#### 4.1 `scripts/powershell/common.ps1`

```powershell
function Find-ReferenceDocs {
    param([string]$FeatureDir)

    $refsDir = Join-Path $FeatureDir "references"
    $refs = @()

    if (Test-Path $refsDir) {
        $files = Get-ChildItem -Path $refsDir -File
        foreach ($file in $files) {
            $refs += $file.Name
        }
    }

    return $refs
}

function Get-ReferenceDocsJson {
    param([string]$FeatureDir)

    $refs = Find-ReferenceDocs -FeatureDir $FeatureDir

    if ($refs.Count -eq 0) {
        return "[]"
    }

    $jsonRefs = ($refs | ForEach-Object { "`"$_`"" }) -join ","
    return "[$jsonRefs]"
}
```

---

## File Change Summary

| File | Changes |
|------|---------|
| `scripts/bash/common.sh` | Add `find_reference_docs()`, `get_reference_docs_json()`, update `get_feature_paths()` |
| `scripts/bash/check-prerequisites.sh` | Add references to AVAILABLE_DOCS, add REFERENCE_DOCS to JSON |
| `scripts/bash/create-new-feature.sh` | Create references/ dir, add to JSON output |
| `scripts/powershell/common.ps1` | Add equivalent PowerShell functions |
| `scripts/powershell/check-prerequisites.ps1` | Mirror bash changes |
| `scripts/powershell/create-new-feature.ps1` | Mirror bash changes |
| `templates/spec-template.md` | Add Reference Documents section |
| `templates/plan-template.md` | Add Reference Document Analysis section |
| `templates/commands/specify.md` | Add step to load references |
| `templates/commands/plan.md` | Add step to load references |
| `templates/commands/clarify.md` | Reference docs when clarifying |
| `templates/commands/tasks.md` | Include references for context |

---

## Usage Example

After implementation, the workflow would be:

1. **User creates feature with reference docs**:
   ```
   /speckit.specify Add OAuth2 authentication
   ```

2. **User adds reference documents**:
   ```bash
   # Copy PRD, design docs, etc. to references/
   cp ~/docs/auth-prd.md specs/001-oauth-auth/references/
   cp ~/docs/api-contract.yaml specs/001-oauth-auth/references/
   ```

3. **User runs plan command**:
   ```
   /speckit.plan Using Node.js with Express
   ```
   - Plan command detects references/
   - Loads auth-prd.md and api-contract.yaml
   - Incorporates requirements into plan
   - Context is maintained from source documents

---

## Testing Plan

1. **Script Tests**:
   - Create feature with empty references/
   - Create feature with multiple reference files
   - Verify JSON output includes REFERENCE_DOCS array
   - Verify references/ directory is created

2. **Command Tests**:
   - Run /speckit.specify with reference docs present
   - Verify spec includes reference summary
   - Run /speckit.plan with reference docs
   - Verify plan incorporates reference constraints

3. **Integration Tests**:
   - Full workflow: specify → plan → tasks with reference docs
   - Verify context from reference docs flows through all artifacts
