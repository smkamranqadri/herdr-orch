# Plan: fixes from the 2026-10-25 eval run

Date: 2026-10-25. Owner: the user. Mode: Standard. Scope approved 2026-10-25.

## Problem

The eval run (State, Evals) found: eval 4 failed on both hosts because the orchs waited with
`agent prompt ... --wait` instead of `wait-turn.sh`, which the `SKILL.md` follow-up example
shows; a Codex orch proposed workers in a question dialog instead of printed lines (eval 1);
`SKILL.md` says Codex shows no trust prompt, but it did in every eval sandbox; and the watcher
exits on one unparseable `herdr agent get` read. Add nothing unnecessary to the skill or KIS.

## Decisions (owner, 2026-10-25)

- The whole "Sending prompts" follow-up passage, example and prose, sends with `agent prompt`
  and no `--wait`, then tracks the turn with `wait-turn.sh` in the background (see Track
  workers); no text recommends `--wait` or `agent_prompt_stalled` recovery.
- "Propose workers": print the lines as plain text in the reply, never a question dialog.
- The Codex trust-prompt sentence quotes the prompt the evals showed ("Folder access <folder>
  Trust this folder? ... › 1. Trust and continue / 2. Quit") and answers it with
  `herdr agent send-keys <name> enter` when it names the worker's recorded launch folder.
- `wait-turn.sh` retries a read that is unparseable or has no `result.agent`: one read plus up
  to 3 retries, 4 reads in all, 1 second apart, then `error`; a Herdr error code (`gone`
  included) is reported after one read.
- `evals/evals.json` eval 1: the proposal expectation adds "as plain text in the reply, not a
  question dialog".
- Proof: re-run only the failed cells (Claude eval 4, Codex eval 4, Codex eval 1) with the same
  models and efforts; before the Codex cells the owner runs
  `./bootstrap.sh update --source . --claude-automode yes`, since Codex reads the installed copy.
- 0.4.0 is unreleased: add to its CHANGELOG section.

## Tasks

- [x] 1. `SKILL.md`: the follow-up passage, the proposal rule and the Codex trust sentence;
  `evals/evals.json` eval 1 proposal expectation.
- [x] 2. `wait-turn.sh` retry; `tests/test-wait-turn.sh` cases, each asserting the exact
  `agent get` count and fake-clock sleeps: unparseable then good, no `result.agent` then good,
  bad on all 4 reads (`error`), and a Herdr error code (one read, no retry); break the retry
  and watch the cases fail.
- [x] 3. `CHANGELOG.md` 0.4.0 lines.
- [x] 4. Re-run Claude eval 4, then, after the owner's update, Codex eval 4 and Codex eval 1,
  as [eval-run.md](eval-run.md) runs them; grade, retire, and update State's Evals table.

## Out of scope

Other eval cells, other `evals/evals.json` changes, the Codex `Killed` item, pushing or releasing.

## Acceptance

- `tests/run.sh` passes with the two new cases; breaking the retry trips them.
- `SKILL.md` stays under 500 lines.
- The three re-run cells pass every behaviour, or the failure is recorded in State.

## Risks and assumptions

- One run per cell is one data point.
- The retry adds at most 3 seconds before a real outage is reported.

## Review
- Reviewed: 2026-10-25 by codex gpt-6.1-sol (low); plan hash b98496a6c699
- [fixed] The retry tests would not prove the limit or the 1 s spacing - 4 reads in all, and each case asserts exact agent get counts and fake-clock sleeps, for both bad-read kinds, plus a Herdr error code read once
- [fixed] Task 1 left the prose next to the example recommending --wait and agent_prompt_stalled recovery - the whole follow-up passage is rewritten
- [fixed] AGENTS.md requires evals.json to follow covered behaviour, and eval 1 could not tell printed lines from a dialog - eval 1's proposal expectation adds "as plain text in the reply, not a question dialog" (owner approved the scope change)
