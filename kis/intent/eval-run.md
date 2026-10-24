# Plan: run the four eval scenarios

Date: 2026-10-25. Owner: the user. Mode: Standard. Scope approved 2026-10-25.

## Problem

The scenarios in `evals/evals.json` last ran on 2026-10-24 against 0.1.0, before the fixes that
run found; scenario 4 `idle-finish` has never run. The fixes are unproven by eval. Add nothing
unnecessary to the skill or KIS.

## Decisions (owner, 2026-10-25)

- Run after `/kis:act` on [command-code.md](command-code.md) and
  [remove-plan-mode.md](remove-plan-mode.md), against the repo's skill at that point.
- With the skill only, on two hosts: Claude Code, Sonnet 5.5 medium, launched with
  `--dangerously-skip-permissions`; Codex, `gpt-6.1-sol` medium, launched with `--sandbox
  danger-full-access -a never`. No no-skill baselines (the 2026-10-24 ones stand).
- Eight runs, one at a time. Each gets a new sandbox from `evals/setup.sh <dir> <id>
  --with-skill <absolute path to the repo's skills/herdr-orch>` (setup.sh changes directory
  first), so the installed copy is untouched. Evals 2 and 4 get a `notes` helper, haiku low,
  per their setup text. An agent's first turn after launch is watched from baseline `0`; a
  later turn from the `completion_seq` recorded before it.
- Grade every `expected_behavior` line pass or fail from the eval orch's screen, files and Herdr
  state, citing the evidence. A question from the eval orch is recorded and left unanswered.
- Results replace State's Evals section; each failure becomes a Next item with its evidence.
  Nothing is fixed in this plan.

## Tasks

- [ ] 1. Claude Code runs, evals 1-4: set up, launch, watch, grade, retire.
- [ ] 2. Codex runs, evals 1-4: the same.
- [ ] 3. Rewrite State's Evals section with dates, versions and the grade table; add a Next item
  per failure.

## Out of scope

No-skill baselines, fixing failures, changing `evals/evals.json` or `evals/setup.sh`, pushing or
releasing.

## Acceptance

- Eight graded runs recorded with dates and versions, each grade with its evidence.
- `herdr agent list` shows no eval agent at the end.
- Every failure is a Next item.

## Risks and assumptions

- One run per cell is one data point.
- Codex usage near its 5-hour limit may mean waiting for the reset.
- The grades are the orch's judgment; the cited evidence lets the owner check them.

## Review
- Reviewed: 2026-10-25 by codex gpt-6.1-sol (low); plan hash 88a4a174ed85
- [fixed] --with-skill skills/herdr-orch is relative, and setup.sh changes into the sandbox first - pass the absolute path
- [fixed] Baseline 0 for every agent conflicts with the eval 2 and 4 helpers, which have already run a turn - 0 for a first turn after launch, the recorded completion_seq for later turns
