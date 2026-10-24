# Current

Stamp: main 6fcd718 d76292a3facc

Status: 0.1.0 released 2026-10-24 (commit 6fcd718). KIS initialized; not yet committed.

## Evals

`evals/` (spawn-gate, stale-done, out-of-claim) ran once per scenario on 2026-10-24: with and
without the skill on Claude Code 2.1.300 (Sonnet 5.5), and with it only on Codex 0.162.1 (no
Codex baseline; Codex loaded the owner's global memory). Three gaps found were
fixed in 0.1.0. The scenarios have not been re-run since those fixes, so the fixes are unproven
by eval.

## Proof

- Watcher prototype (`wait-turn-event.sh`, scratchpad), 2026-10-24: backstop on an idle agent after
  exactly 60 s; `error` exit 1 on an unknown agent; watching the round-2 plan reviewer it woke
  this session once, `finished seq=148 status=done srv=10356311 waited=249s` at 20:33:00.
- Live test in a second orch since 20:19:
  result pending.

## Now

No task in progress.

## Next

1. Watcher fix: event-mode plan reviewed twice (codex gpt-6.1-sol, 11 findings fixed);
   ready for `/kis:act`: [watcher-fix.md](../intent/watcher-fix.md).
2. Add a PERMS column to the worker proposal so auto mode lets launches through (owner
   request, 2026-10-24; untested): [perms-column.md](../intent/perms-column.md).
3. Add Command Code as a supported agent (owner's next task, 2026-10-24); scope it with
   `/kis:plan` first.
4. Support several orchs in one project (owner request, 2026-10-24); scope it with `/kis:plan`
   first. Goal and collision points: [multi-orch.md](../intent/multi-orch.md).
5. Re-run the three eval scenarios against the current version to prove the fixes, after the
   owner approves the harness, model and effort.
