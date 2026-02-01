# References

Sprint-based reference documents for speckit commands.

## Quick Start

1. Create a sprint directory:
   ```bash
   mkdir -p references/sprint-1
   ```

2. Add your docs:
   ```bash
   cp ~/docs/prd.md references/sprint-1/
   cp ~/docs/architecture.md references/sprint-1/
   ```

3. Run speckit commands normally — docs auto-load for `specify` and `plan`.

## How It Works

| Command | Loads References? |
|---------|-------------------|
| `specify` | Yes (WHAT) |
| `plan` | Yes (HOW) |
| `clarify`, `tasks`, `implement`, etc. | No (read artifacts) |

- Docs load **once per artifact** (spec.md, plan.md), then skip
- Each feature loads docs independently
- Modified docs re-load automatically (checksum detection)

## Directory Structure

```
references/
├── .current-sprint      # Optional: override auto-detection
├── sprint-1/
│   ├── prd.md
│   ├── architecture.md
│   └── .references-state.json  # Auto-generated manifest
└── sprint-2/
    └── new-requirements.md
```

## Sprints Without Docs

Just don't create the directory — speckit works normally without references.

```bash
# Override to empty sprint (no docs)
echo "sprint-2" > references/.current-sprint
```

## Debug

```bash
# See what would be loaded
./scripts/bash/check-references.sh --json --command=specify --feature=001-auth --target=spec.md

# Inspect manifest
cat references/sprint-1/.references-state.json | jq .

# Force reload (delete manifest)
rm references/sprint-1/.references-state.json
```

## Full Design

See `docs/study/07-smart-reference-loading.md` for the complete technical design.
