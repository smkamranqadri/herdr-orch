# Agent Instructions

This repository is the **source** of the **herdr-orch** skill. Nothing here is a live install:
`skills/` sits outside every host's discovery path. To use it, install into a home with
`bootstrap.sh`.

## Layout

```text
skills/herdr-orch/     the skill, and what ships
  SKILL.md             the orch workflow; loaded when the skill is invoked
  agents/openai.yaml   Codex display name and invocation policy
scripts/               install-skill.sh, run from a source clone only
evals/                 three scenarios (evals.json) and their sandbox builder (setup.sh)
docs/assets/           the README images (never installed)
tests/                 one suite per area, run by tests/run.sh (never installed)
.github/workflows/     CI: tests/run.sh on Linux
bootstrap.sh           one-command install, check, update
```

## Rules for changes

- Keep `SKILL.md` under 500 lines and every reference one link deep from it.
- Name only Herdr commands and flags that exist; `tests/test-skill.sh` checks them against the
  installed Herdr.
- A change to what the orch does comes with an update to `evals/evals.json` when a scenario
  covers it, and a line in `CHANGELOG.md`. Bump `metadata.version` for any change that ships.
- Run `tests/run.sh` before calling a change done.

<!-- kis:anchor:start -->
## KIS Project Memory

This project uses KIS memory under `kis/`. Knowledge = stable facts. Intent = goals and plans. State = current reality.

- Read `kis/state/` before planning or implementing, then only the Intent and Knowledge the task needs.
- Put each fact in exactly one layer, and update an existing file instead of creating a new one.
- Prove work with real command or verification output before marking anything done.
- Synchronize the KIS layers that changed when work finishes.
- Full instructions: `.agents/skills/kis/SKILL.md`.
- Commands live in `.agents/skills/kis/commands/`: start, plan, act, sync, check, init.
  Claude `/kis:start`, Pi and OpenCode `/kis-start`, Codex `/prompts:kis-start`.
  Antigravity has no custom slash commands: name the step and follow its command file.
<!-- kis:anchor:end -->
