# Commands Reference

## Overview

Spec-Kit provides 9 commands for AI agents to execute the Spec-Driven Development workflow. Commands are defined in `/templates/commands/` as Markdown files with YAML frontmatter.

---

## Command Definition Structure

Every command follows this template:

```yaml
---
description: Brief description of what the command does
handoffs:
  - label: Next Action Label
    agent: speckit.next-command
    prompt: Suggested prompt for next command
    send: true  # Optional: auto-send to next agent
scripts:
  sh: scripts/bash/script-name.sh --json "{ARGS}"
  ps: scripts/powershell/script-name.ps1 -Json "{ARGS}"
agent_scripts:  # Optional: for updating agent context
  sh: scripts/bash/update-agent-context.sh __AGENT__
  ps: scripts/powershell/update-agent-context.ps1 -AgentType __AGENT__
---

## User Input
```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Outline
[Detailed execution steps...]
```

---

## Core Commands

### 1. `/speckit.constitution`
**Purpose**: Define or update project governing principles

**Input**: Principles description (`$ARGUMENTS`)

**Output**:
- Updated `/memory/constitution.md`
- Sync impact report

**Key Behavior**:
- Identifies placeholder tokens `[ALL_CAPS_IDENTIFIER]`
- Collects values from user input and existing context
- Propagates changes to dependent templates
- Uses semantic versioning for constitution

---

### 2. `/speckit.specify`
**Purpose**: Create feature specifications from natural language descriptions

**Input**: Feature description (`$ARGUMENTS`)

**Output**:
- Git branch `###-feature-name`
- `specs/###-feature/spec.md`
- `specs/###-feature/checklists/requirements.md`

**Script**: `create-new-feature.sh --json "{ARGS}"`

**Returns**:
```json
{
  "BRANCH_NAME": "001-feature-name",
  "SPEC_FILE": "/path/to/specs/001-feature/spec.md",
  "FEATURE_NUM": "001"
}
```

**Key Behavior**:
- Auto-increments feature number from branches + specs dirs
- Generates semantic branch name (stops word filtering)
- Enforces GitHub 244-byte branch name limit
- Creates user stories with priorities (P1, P2, P3)
- Marks ambiguities with `[NEEDS CLARIFICATION: ...]`

---

### 3. `/speckit.clarify`
**Purpose**: Ask structured questions about ambiguous areas

**Input**: Optional guidance

**Output**: Updated spec.md with clarifications recorded

**Key Behavior**:
- Scans spec for coverage gaps using taxonomy:
  - Functional scope & behavior
  - Domain & data model
  - Interaction & UX flow
  - Non-functional attributes
  - Integration & dependencies
  - Edge cases & failure handling
- Generates max 5 prioritized questions
- Records answers in `## Clarifications` section
- Saves spec after each integration (atomic updates)

---

### 4. `/speckit.plan`
**Purpose**: Create technical implementation plans

**Input**: Optional tech stack hints (`$ARGUMENTS`)

**Output**:
- `specs/###-feature/plan.md`
- `specs/###-feature/research.md` (Phase 0)
- `specs/###-feature/data-model.md` (Phase 1)
- `specs/###-feature/contracts/` (Phase 1)
- `specs/###-feature/quickstart.md` (Phase 1)
- Updated agent context files

**Script**: `setup-plan.sh --json`

**Returns**:
```json
{
  "FEATURE_SPEC": "/path/spec.md",
  "IMPL_PLAN": "/path/plan.md",
  "SPECS_DIR": "/path/specs/###-feature",
  "BRANCH": "###-feature-name",
  "HAS_GIT": "true"
}
```

**Key Behavior**:
- Loads spec.md and constitution.md
- Fills Technical Context (language, deps, storage, testing)
- Constitution Check (validates against principles)
- Phase 0: Research (resolves unknowns)
- Phase 1: Design (entities, contracts, test scenarios)
- Runs `update-agent-context.sh` to sync agent files

---

### 5. `/speckit.analyze`
**Purpose**: Cross-artifact consistency analysis (non-destructive)

**Input**: None

**Output**: Markdown report (console output, not written to file)

**Analysis Passes**:
- Duplication detection
- Ambiguity detection
- Underspecification (requirements with no tasks)
- Constitution alignment
- Coverage gaps
- Inconsistency (terminology drift)

**Output Format**:
- Findings table with severity levels
- Coverage summary
- Unmapped tasks
- Metrics (coverage %)

---

### 6. `/speckit.checklist`
**Purpose**: Generate quality validation checklists

**Input**: Focus domain/area (`$ARGUMENTS`)

**Output**: `specs/###-feature/checklists/{domain}.md`

**Key Behavior**:
- "Unit Tests for Requirements" - validates spec quality
- Dimensions tested:
  - Requirement Completeness/Clarity/Consistency
  - Acceptance Criteria Quality
  - Scenario & Edge Case Coverage
  - Non-Functional Requirements
- Each run creates NEW file, never overwrites

---

### 7. `/speckit.tasks`
**Purpose**: Generate actionable task lists

**Input**: None

**Output**: `specs/###-feature/tasks.md`

**Task Format**:
```
- [ ] [T001] [P?] [Story?] Description with file path
```
- `[ ]` - Markdown checkbox
- `T001` - Sequential ID in execution order
- `[P]` - Parallelizable marker (optional)
- `[Story]` - User story label like [US1] (setup phase: NO label)

**Organization**:
- Phase 1: Setup (project init)
- Phase 2: Foundational (blocking prerequisites)
- Phase 3+: User Stories (in priority order)
- Final: Polish & cross-cutting

---

### 8. `/speckit.implement`
**Purpose**: Execute implementation based on plans and tasks

**Input**: Confirmation (if checklists incomplete)

**Output**:
- Implementation code
- Tests
- Ignore files (.gitignore, .dockerignore)

**Prerequisites Check**:
1. Loads tasks.md, plan.md
2. Optionally: data-model.md, contracts/, research.md
3. Scans checklist status - halts if incomplete
4. Verifies/creates ignore files

---

### 9. `/speckit.taskstoissues`
**Purpose**: Convert tasks to GitHub issues

**Input**: None

**Output**: GitHub issues created via `gh` CLI

---

## Handoff System

Commands define handoff connections in frontmatter:

```yaml
handoffs:
  - label: Build Technical Plan
    agent: speckit.plan
    prompt: Create a plan for the spec. I am building with...
  - label: Clarify Spec Requirements
    agent: speckit.clarify
    prompt: Clarify specification requirements
    send: true
```

**Handoff Elements**:
- `label` - Human-readable action
- `agent` - Target command (speckit.specify, speckit.plan, etc.)
- `prompt` - Suggested prompt
- `send` - Whether to auto-send (optional)

---

## Input/Output Summary

| Command | Input Source | Output Location |
|---------|-------------|-----------------|
| constitution | `$ARGUMENTS` | `/memory/constitution.md` |
| specify | `$ARGUMENTS` | `specs/###/spec.md`, branch |
| clarify | `$ARGUMENTS` (optional) | `specs/###/spec.md` (updated) |
| plan | `$ARGUMENTS` (optional) | `specs/###/plan.md`, research.md, etc. |
| analyze | None | Console report |
| checklist | `$ARGUMENTS` | `specs/###/checklists/{name}.md` |
| tasks | None | `specs/###/tasks.md` |
| implement | Confirmation | Code, tests, ignore files |
| taskstoissues | None | GitHub issues |

---

## Placeholder System

Templates use these placeholders:

| Placeholder | Description | Substituted By |
|-------------|-------------|----------------|
| `$ARGUMENTS` | User input after command | Markdown agents |
| `{{args}}` | User input after command | TOML agents (Gemini, Qwen) |
| `{SCRIPT}` | Script command from YAML | Build script |
| `{AGENT_SCRIPT}` | Agent context update script | Build script |
| `{ARGS}` | Runtime argument placeholder | Build script |
| `__AGENT__` | Agent identifier | Build script |
