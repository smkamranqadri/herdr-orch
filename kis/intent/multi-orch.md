# Plan: several orchs in one project

Date: 2026-10-25. Owner: the user. Mode: Standard. Scope approved 2026-10-25.

## Problem

Several orchs can run at once in one repo on one Herdr server, possibly in one workspace.
`SKILL.md` assumes a single orch. Collisions found 2026-10-24: agent names, brief folders and
worktree branches built from the same slug; two orchs merging into the main checkout; two orchs
handing the same file to different workers; tabs of other orchs in a shared workspace. Add
nothing unnecessary to the skill or KIS.

## Decisions (owner, 2026-10-25)

- Each orch picks an orch id at preflight: its task slug (for example `perms`), checked unused:
  no live agent in `herdr agent list`, no `<id>-*` branch and no `herdr-orch/<id>/` folder. It
  prefixes agent names (`perms-fix-loops`),
  worktree branches (the same as the agent name) and the brief folder
  (`${TMPDIR:-/tmp}/herdr-orch/<orch-id>/`). The whole `<orch-id>-<slice>` name must match the
  existing agent-name pattern. Tab labels do not change.
- An orch reads, prompts, retires and removes only the tabs, panes, agents and worktrees in its
  own registry, plus agents the owner names, recorded in the registry first; anything else
  belongs to another orch or the owner and is read-only to it.
- Before integrating: the main checkout's `git status` is clean, with no merge, rebase or
  cherry-pick in progress; otherwise stop and tell the owner. No lock file.
- Before merging, trial-merge the worker's committed branch tip against current main with
  `git merge-tree --write-tree main <branch>` (uncommitted work is committed first); a conflict
  goes to the owner. No claims file.
- 0.3.0 is unreleased: no version bump.

## Tasks

- [x] 1. `SKILL.md`: the orch id in Preflight; the prefix in the naming rule, the worktree
  `--branch` and the brief path; the registry-only rule in Invariants; the clean-checkout and
  trial-merge checks in "Verify worker output". The example names become `perms-fix-loops` and
  `perms-audit-auth` throughout `SKILL.md` (`references/plan-mode.md` is left alone: the owner
  will remove plan mode).
- [x] 2. `evals/evals.json` spawn-gate: the brief path is `${TMPDIR:-/tmp}/herdr-orch/<orch-id>/`.
- [x] 3. `CHANGELOG.md` 0.3.0 line.

## Out of scope

Lock or claims files, tab label changes, a live run with two orchs, the other Next items,
pushing or releasing.

## Acceptance

- `tests/run.sh` passes; `test-skill.sh` confirms every Herdr command the new text names.
- `SKILL.md` stays under 500 lines.
- `grep` finds the brief path only as `herdr-orch/<orch-id>/`, and no unprefixed `fix-loops`
  or `audit-auth` is left in `SKILL.md`.

## Risks and assumptions

- Whether Herdr rejects a duplicate agent name is unverified; the prefix and the `agent list`
  check cover both cases.
- The rules work only if every orch follows them; an orch on 0.2.x does not.
- A trial merge catches textual conflicts only; two orchs editing related code without one can
  still break main, which the post-merge gate has to catch.

## Review
- Reviewed: 2026-10-25 by codex gpt-6.1-sol (medium); plan hash d9430f874184
- [rejected] Clean-status and trial-merge checks do not serialize integration - git already refuses to merge over a merge in progress or a dirty index; the check makes the orch stop, and owner-run serialization is heavier than the goal
- [fixed] An unused live-agent prefix does not reserve an orch id - the check also covers existing <id>-* branches and the brief folder; a random suffix was rejected, since the owner starts orchs one at a time
- [rejected] A clean merge-tree misses incompatible edits without textual conflicts - the owner chose no claims file; recorded under Risks
- [fixed] merge-tree checks committed contents while eval 3 has an uncommitted diff - trial-merge the committed branch tip, committing the work first
- [fixed] The registry-only rule blocks owner-named existing workers (evals 2 and 4) - agents the owner names are allowed once recorded in the registry
- [fixed] A prefix can push a name past the 32-character pattern - the whole <orch-id>-<slice> name must match it
- [fixed] Prefixing only the proposal example leaves launch and follow-up examples inconsistent - the example names are prefixed throughout SKILL.md
