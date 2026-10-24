# Current

Stamp: main 6fcd718 d76292a3facc

Status: 0.1.0 released 2026-10-24 (commit 6fcd718). KIS initialized; not yet committed.

## Evals

`evals/` (spawn-gate, stale-done, out-of-claim) ran once per scenario on 2026-10-24: with and
without the skill on Claude Code 2.1.300 (Sonnet 5.5), and with it only on Codex 0.162.1 (no
Codex baseline; Codex loaded the owner's global memory). Three gaps found were
fixed in 0.1.0. The scenarios have not been re-run since those fixes, so the fixes are unproven
by eval.

## Now

No task in progress.

## Next

1. Add Command Code as a supported agent (owner's next task, 2026-10-24); scope it with
   `/kis:plan` first.
2. Re-run the three eval scenarios against the current version to prove the fixes, after the
   owner approves the harness, model and effort.
