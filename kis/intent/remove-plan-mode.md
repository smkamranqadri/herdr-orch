# Plan: remove plan-first delegation

Date: 2026-10-25. Owner: the user. Mode: Standard. Scope approved 2026-10-25.

## Problem

The skill carries plan-first delegation: a `SKILL.md` section and `references/plan-mode.md`
(187 lines) for running workers in Claude's or Codex's plan mode. The owner plans with KIS before
delegating, so it is not needed. Add nothing unnecessary to the skill or KIS.

## Decisions (owner, 2026-10-25)

- Remove it with no replacement and no line saying it is gone; the orch delegates direct.
- `references/` goes with its only file.
- Version: Command Code and this change are both unreleased; whichever lands first bumps to
  0.4.0, the other adds to that section. The CHANGELOG says "Removed: plan-first delegation".

## Tasks

- [ ] 1. Delete `skills/herdr-orch/references/plan-mode.md` and the `references/` folder.
- [ ] 2. `SKILL.md`: remove the "Plan-first delegation" section, the packet's execution-mode
  field, the plan-mode launch notes (including the "Codex plan-first launches bare" exception
  in "Sending prompts"), the planning statuses in the registry list and the
  plan-mode stop condition; the `--match` example no longer names a plan-mode menu.
- [ ] 3. `README.md` plan-first bullet; the `AGENTS.md` layout line; in `CONTRIBUTING.md` the
  layout line and the passages that send plan-mode detail to `references/`;
  `tests/test-install.sh` drops its `references/plan-mode.md` check.
- [ ] 4. `CHANGELOG.md` 0.4.0 "Removed" line, and `metadata.version` 0.4.0 if not bumped yet.

## Out of scope

A replacement planning step, installer changes, the other Next items, pushing or releasing.

## Acceptance

- `tests/run.sh` passes.
- `grep -riE 'plan-first|plan mode|plan-mode|permission-mode plan'` over `skills/`, `README.md`,
  `AGENTS.md`, `CONTRIBUTING.md` and `tests/` finds nothing, and `skills/herdr-orch/references/`
  does not exist.

## Risks and assumptions

- An installed 0.3.0 keeps plan mode until the owner runs `bootstrap.sh update`, which replaces
  the whole skill folder.

## Review
- Reviewed: 2026-10-25 by codex gpt-6.1-sol (low); plan hash 6275cf786384
- [fixed] Task 2 missed the "Codex plan-first launches bare" exception in "Sending prompts", which would dangle - named in task 2
- [fixed] Task 3 covered only CONTRIBUTING's layout line, not its passages sending plan-mode detail to references/ - task 3 covers them
