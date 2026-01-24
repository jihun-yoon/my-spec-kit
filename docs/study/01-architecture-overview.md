# Spec-Kit Architecture Overview

## What is Spec-Kit?

Spec-Kit is an open-source toolkit for implementing **Spec-Driven Development (SDD)** - a methodology where specifications are the primary artifact that drives development, rather than code being the source of truth with specifications as afterthoughts.

### Core Philosophy
- Specifications become executable, directly generating working code
- AI assists in transforming specs into plans and implementations
- Development focuses on intent and product scenarios

---

## Repository Structure

```
my-spec-kit/
├── .devcontainer/           # Dev container configuration
├── .github/                 # GitHub Actions workflows
│   └── workflows/           # CI/CD (release.yml, lint.yml, docs.yml)
│       └── scripts/         # Release automation scripts
├── docs/                    # Documentation site (DocFX)
├── media/                   # Marketing assets (GIFs, logos)
├── memory/                  # Project memory/context
│   └── constitution.md      # Project principles & guidelines
├── scripts/                 # Automation scripts
│   ├── bash/               # POSIX shell scripts
│   └── powershell/         # Windows PowerShell scripts
├── src/                    # Python source code
│   └── specify_cli/        # Main CLI implementation
├── templates/              # Project templates
│   ├── commands/           # AI agent command definitions (9 commands)
│   ├── spec-template.md    # Specification template
│   ├── plan-template.md    # Plan template
│   ├── tasks-template.md   # Tasks template
│   └── ...
├── pyproject.toml          # Python package config
├── README.md               # Main documentation
├── AGENTS.md               # Agent integration docs
└── spec-driven.md          # SDD methodology guide
```

---

## Project Type

- **Python CLI Tool**: `specify-cli` - Command-line tool for bootstrapping SDD projects
- **Template Repository**: Contains agent-specific project structures
- **AI Integration Framework**: Supports 18+ code assistants

### Key Dependencies
- `typer` - CLI framework
- `rich` - Terminal UI rendering
- `httpx` - HTTP client for GitHub API
- `platformdirs` - Cross-platform paths
- `readchar` - Keyboard input

---

## Main Entry Points

### 1. `specify init [PROJECT_NAME]`
Initialize new Spec-Kit projects:
- Downloads templates from GitHub releases
- Sets up agent-specific directories (.claude/, .gemini/, etc.)
- Initializes git repository
- Options: `--ai`, `--script`, `--here`, `--no-git`

### 2. `specify check`
Verify installation of required tools:
- Checks for git, code editors, AI agent CLIs

### 3. `specify version`
Display version and system information

---

## Supported AI Agents (18+)

| Agent | Directory | CLI Tool |
|-------|-----------|----------|
| Claude Code | `.claude/commands/` | `claude` |
| GitHub Copilot | `.github/agents/` | N/A |
| Gemini CLI | `.gemini/commands/` | `gemini` |
| Cursor | `.cursor/commands/` | `cursor-agent` |
| Windsurf | `.windsurf/workflows/` | N/A |
| Qwen Code | `.qwen/commands/` | `qwen` |
| Amazon Q | `.amazonq/prompts/` | `q` |
| opencode | `.opencode/command/` | `opencode` |
| Codex CLI | `.codex/commands/` | `codex` |
| ... | ... | ... |

---

## Workflow Overview

```
User Feature Request
        ↓
/speckit.constitution  →  Define project principles
        ↓
/speckit.specify      →  Create specifications
        ↓
/speckit.clarify      →  (Optional) Ask clarifying questions
        ↓
/speckit.plan         →  Create implementation plans
        ↓
/speckit.analyze      →  (Optional) Consistency analysis
        ↓
/speckit.checklist    →  (Optional) Generate quality checklists
        ↓
/speckit.tasks        →  Generate actionable task lists
        ↓
/speckit.implement    →  Execute implementation
        ↓
/speckit.taskstoissues → (Optional) Convert to GitHub issues
```

---

## Key Configuration Files

| File | Purpose |
|------|---------|
| `pyproject.toml` | Python package metadata, dependencies |
| `memory/constitution.md` | Project governance & principles |
| `AGENTS.md` | Agent integration patterns |
| `.github/workflows/release.yml` | Automated release creation |
| `docs/docfx.json` | Documentation site config |

---

## Release Process

1. Template commands in `/templates/commands/*.md` are the source of truth
2. Build script generates agent-specific packages for each combination:
   - Agent (claude, gemini, copilot, etc.)
   - Script type (sh, ps)
3. Creates release archives: `spec-kit-template-{agent}-{script}-{version}.zip`
4. Publishes to GitHub Releases
