# Context Handling Analysis

## Overview

This document analyzes how Spec-Kit currently handles context, requirements, and user input - and identifies the key limitation: **context is gathered only from user input (chat) and auto-generated artifacts, not from external reference documents**.

---

## Current Context Architecture

### Multi-Level Context System

```
Level 1: Global (Project-wide)
├── /memory/constitution.md     ← Project principles, loaded by all commands
└── Agent context files         ← Auto-generated from plan.md

Level 2: Feature-specific
└── /specs/###-feature/
    ├── spec.md                 ← User stories, requirements
    ├── plan.md                 ← Technical architecture
    ├── research.md             ← Technical decisions
    ├── data-model.md           ← Entity definitions
    ├── contracts/              ← API specifications
    ├── quickstart.md           ← Test scenarios
    ├── tasks.md                ← Implementation tasks
    └── checklists/             ← Quality validation

Level 3: Runtime
└── $ARGUMENTS                  ← User input from chat (ONLY source of new context)
```

---

## How Context Flows Between Commands

### Sequential Workflow

```
/speckit.specify
    Input:  $ARGUMENTS (feature description from chat)
    Output: spec.md
            ↓
/speckit.clarify (optional)
    Input:  $ARGUMENTS + spec.md
    Output: spec.md (updated with clarifications)
            ↓
/speckit.plan
    Input:  $ARGUMENTS + spec.md + constitution.md
    Output: plan.md, research.md, data-model.md, contracts/
            ↓
/speckit.tasks
    Input:  plan.md + optional docs (data-model, contracts, research)
    Output: tasks.md
            ↓
/speckit.implement
    Input:  All artifacts + checklists
    Output: Code, tests
```

---

## Context Sources by Command

| Command | User Input | Loaded Context |
|---------|-----------|----------------|
| constitution | `$ARGUMENTS` | Existing constitution.md, templates |
| specify | `$ARGUMENTS` | None (generates fresh) |
| clarify | `$ARGUMENTS` (optional) | spec.md |
| plan | `$ARGUMENTS` (optional) | spec.md, constitution.md |
| analyze | None | spec.md, plan.md, tasks.md, constitution.md |
| checklist | `$ARGUMENTS` | spec.md, plan.md, tasks.md |
| tasks | None | plan.md, data-model.md, contracts/, research.md |
| implement | Confirmation | All artifacts |

---

## The Context Problem

### Current Limitation

**All new context comes from a single source: `$ARGUMENTS` (user chat input)**

The system does NOT support:
- Loading external reference documents
- Referencing existing codebase documentation
- Including PRDs, design docs, or other specifications
- Maintaining context from attached files

### Why This Causes Context Loss

1. **Large features require multiple chat turns**
   - User can't paste entire PRD into `$ARGUMENTS`
   - Context from previous messages gets summarized/lost

2. **No mechanism to reference external docs**
   - Can't say "see requirements in docs/prd.md"
   - System only knows what's in spec/plan/tasks artifacts

3. **Constitution is global, not feature-specific**
   - Feature-specific reference docs have no designated place
   - Must be manually included in spec.md

4. **Scripts return paths, not content**
   - `check-prerequisites.sh` returns AVAILABLE_DOCS list
   - But commands don't actually load those docs into context

---

## How Context is Currently Gathered

### 1. User Input Extraction

From command templates:
```markdown
## User Input
```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).
```

The text after the slash command becomes `$ARGUMENTS`:
```
/speckit.specify Add user authentication with OAuth support
                 ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                 This becomes $ARGUMENTS
```

### 2. Script JSON Output

Scripts return structured data about existing artifacts:
```json
{
  "FEATURE_DIR": "/path/to/specs/001-feature",
  "FEATURE_SPEC": "/path/to/specs/001-feature/spec.md",
  "IMPL_PLAN": "/path/to/specs/001-feature/plan.md",
  "AVAILABLE_DOCS": ["research.md", "data-model.md", "contracts/"]
}
```

### 3. Template Loading

Commands instruct AI to load specific files:
```markdown
## Outline

1. Run `{SCRIPT}` and parse JSON output
2. Load context:
   - Read FEATURE_SPEC (spec.md)
   - Read `/memory/constitution.md`
   - Load IMPL_PLAN template
```

### 4. Constitution Propagation

The constitution is loaded for validation gates:
```markdown
## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| [From constitution.md] | PASS/FAIL/N/A | [Justification] |
```

---

## Agent Context File Generation

### Auto-Generated Content

`update-agent-context.sh` parses plan.md and updates agent files:

**Extracted from plan.md**:
- Language/Version
- Primary Dependencies
- Storage systems
- Testing frameworks
- Project Type

**Written to CLAUDE.md/GEMINI.md/etc**:
- Active technologies
- Project structure
- Build/test commands
- Code style guidelines
- Recent changes (last 3 features)

### Limitation

Agent context files are **output-only** - they're generated FROM plan.md, not used as input to gather additional context.

---

## Reference Document Gap

### What's Missing

```
Current System:
User Chat → $ARGUMENTS → spec.md → plan.md → tasks.md → code

Needed:
Reference Docs ──┐
                 ├──→ spec.md → plan.md → tasks.md → code
User Chat ───────┘
```

### Desired Behavior

1. **Reference Document Directory**
   ```
   specs/###-feature/
   ├── references/              ← NEW: External reference docs
   │   ├── prd.md              ← Product requirements
   │   ├── design-doc.md       ← Design specifications
   │   ├── api-contract.yaml   ← API specifications
   │   └── ...
   └── spec.md                 ← Generated spec references docs
   ```

2. **Command Awareness**
   - `/speckit.specify` should scan `references/` and incorporate into spec
   - `/speckit.plan` should load reference docs for technical decisions
   - `/speckit.tasks` should reference original docs for context

3. **Script Support**
   - `check-prerequisites.sh` should detect reference docs
   - JSON output should include `REFERENCE_DOCS` array

4. **Template Updates**
   - spec-template.md should have `## Reference Documents` section
   - Commands should instruct AI to load and synthesize reference docs

---

## Proposed Changes Summary

To add reference document support:

### 1. Directory Structure Change
```
specs/###-feature/
├── references/         ← NEW
├── spec.md
└── ...
```

### 2. Script Changes
- `common.sh`: Add `find_reference_docs()` function
- `check-prerequisites.sh`: Include references in AVAILABLE_DOCS
- `create-new-feature.sh`: Create references/ directory

### 3. Template Changes
- `spec-template.md`: Add reference section
- `plan-template.md`: Add reference loading
- Command templates: Add reference doc loading steps

### 4. Command Changes
- `/speckit.specify`: Load references/ before generating spec
- `/speckit.plan`: Include references in context loading
- `/speckit.clarify`: Reference docs when answering questions

---

## Key Files to Modify

| File | Change |
|------|--------|
| `scripts/bash/common.sh` | Add `find_reference_docs()` |
| `scripts/bash/check-prerequisites.sh` | Add reference detection |
| `scripts/bash/create-new-feature.sh` | Create references/ dir |
| `templates/spec-template.md` | Add reference section |
| `templates/plan-template.md` | Add reference loading |
| `templates/commands/specify.md` | Load references |
| `templates/commands/plan.md` | Load references |
| `templates/commands/clarify.md` | Use references |
| `templates/commands/tasks.md` | Reference docs for context |
