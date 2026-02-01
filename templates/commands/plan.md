---
description: Execute the implementation planning workflow using the plan template to generate design artifacts.
handoffs:
  - label: Create Tasks
    agent: speckit.tasks
    prompt: Break the plan into tasks
    send: true
  - label: Create Checklist
    agent: speckit.checklist
    prompt: Create a checklist for the following domain...
scripts:
  sh: scripts/bash/setup-plan.sh --json
  ps: scripts/powershell/setup-plan.ps1 -Json
agent_scripts:
  sh: scripts/bash/update-agent-context.sh __AGENT__
  ps: scripts/powershell/update-agent-context.ps1 -AgentType __AGENT__
ref_scripts:
  sh: scripts/bash/check-references.sh --json --command=plan --feature={FEATURE} --target=plan.md
  ps: scripts/powershell/check-references.ps1 -Json -Command plan -Feature {FEATURE} -Target plan.md
ref_update_scripts:
  sh: scripts/bash/update-manifest.sh {REFS_DIR} {FEATURE} plan.md
  ps: scripts/powershell/update-manifest.ps1 -RefsDir {REFS_DIR} -Feature {FEATURE} -Target plan.md
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Outline

### Step 0: Load Reference Documents (Optional)

Before starting the planning workflow, check for reference documents:

1. **Check for references**: Run `{REF_SCRIPT}` (replace `{FEATURE}` with the current branch name).

2. **Parse the JSON output**:
   - If `sprint` is `null` → No references found, proceed to step 1 normally
   - If `load` array is empty → All references already incorporated, proceed normally
   - If `load` array has items → Read each file and use as context

3. **Process references to load**:
   For each item in the `load` array:
   - Read the file at the `path` provided
   - Note whether it's `NEW` or `MODIFIED` (state field)
   - Use the content to inform your technical planning

4. **Use reference context**:
   - Reference docs may contain architecture decisions, design patterns, or technical constraints
   - Use this context when filling Technical Context and making design decisions
   - Architecture docs inform technology choices and patterns

5. **Update manifest after completion**:
   After writing plan.md, run `{REF_UPDATE_SCRIPT}` to mark references as incorporated.
   (Replace `{REFS_DIR}` with the `refs_dir` from the check-references output, `{FEATURE}` with branch name)

**Note**: If no `references/sprint-*` directory exists, skip this step entirely.

---

1. **Setup**: Run `{SCRIPT}` from repo root and parse JSON for FEATURE_SPEC, IMPL_PLAN, SPECS_DIR, BRANCH. For single quotes in args like "I'm Groot", use escape syntax: e.g 'I'\''m Groot' (or double-quote if possible: "I'm Groot").

2. **Load context**: Read FEATURE_SPEC, `/memory/constitution.md`, and any loaded reference documents. Load IMPL_PLAN template (already copied).

3. **Execute plan workflow**: Follow the structure in IMPL_PLAN template to:
   - Fill Technical Context (mark unknowns as "NEEDS CLARIFICATION")
   - Fill Constitution Check section from constitution
   - Evaluate gates (ERROR if violations unjustified)
   - Phase 0: Generate research.md (resolve all NEEDS CLARIFICATION)
   - Phase 1: Generate data-model.md, contracts/, quickstart.md
   - Phase 1: Update agent context by running the agent script
   - Re-evaluate Constitution Check post-design

4. **Stop and report**: Command ends after Phase 2 planning. Report branch, IMPL_PLAN path, and generated artifacts.

## Phases

### Phase 0: Outline & Research

1. **Extract unknowns from Technical Context** above:
   - For each NEEDS CLARIFICATION → research task
   - For each dependency → best practices task
   - For each integration → patterns task

2. **Generate and dispatch research agents**:

   ```text
   For each unknown in Technical Context:
     Task: "Research {unknown} for {feature context}"
   For each technology choice:
     Task: "Find best practices for {tech} in {domain}"
   ```

3. **Consolidate findings** in `research.md` using format:
   - Decision: [what was chosen]
   - Rationale: [why chosen]
   - Alternatives considered: [what else evaluated]

**Output**: research.md with all NEEDS CLARIFICATION resolved

### Phase 1: Design & Contracts

**Prerequisites:** `research.md` complete

1. **Extract entities from feature spec** → `data-model.md`:
   - Entity name, fields, relationships
   - Validation rules from requirements
   - State transitions if applicable

2. **Generate API contracts** from functional requirements:
   - For each user action → endpoint
   - Use standard REST/GraphQL patterns
   - Output OpenAPI/GraphQL schema to `/contracts/`

3. **Agent context update**:
   - Run `{AGENT_SCRIPT}`
   - These scripts detect which AI agent is in use
   - Update the appropriate agent-specific context file
   - Add only new technology from current plan
   - Preserve manual additions between markers

**Output**: data-model.md, /contracts/*, quickstart.md, agent-specific file

## Key rules

- Use absolute paths
- ERROR on gate failures or unresolved clarifications
