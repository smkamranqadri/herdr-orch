# Current

Stamp: watcher-fix e948f78 3d35fd051614

Status: 0.1.0 released 2026-10-24 (6fcd718). 0.2.0 (event-mode watcher) committed on branch
`watcher-fix` (f0bcaf0), verified, not merged or released.

## Evals

`evals/` (spawn-gate, stale-done, out-of-claim) ran once per scenario on 2026-10-24: with and
without the skill on Claude Code 2.1.300 (Sonnet 5.5), and with it only on Codex 0.162.1 (no
Codex baseline; Codex loaded the owner's global memory). Three gaps found were
fixed in 0.1.0. The scenarios have not been re-run since those fixes, so the fixes are unproven
by eval. Scenario 4 `idle-finish` (0.2.0) has never been run.

## Proof

- Watcher prototype (`wait-turn-event.sh`, scratchpad), 2026-10-24: backstop on an idle agent after
  exactly 60 s; `error` exit 1 on an unknown agent; watching the round-2 plan reviewer it woke
  this session once, `finished seq=148 status=done srv=10356311 waited=249s` at 20:33:00.
- Live test in a second orch (prototype): `finished seq=151 status=done
  srv=10356311 waited=1598s` at 20:45:55; zero orch API calls from 20:19:30 to the notice
  (session log), against ~3 calls per 5-minute check-in before.
- Branch `watcher-fix`, 2026-10-24: `tests/run.sh` exit 0 (evals, install, skill, wait-turn 29
  cases); 21/21 script mutations tripped their tests, restores byte-identical
  (`$TMPDIR/herdr-orch-mutations.log`); install, eval-id and eval-ids guards tripped;
  `grep -- '--until done' skills/` empty; SKILL.md 363 lines.
- 9a (Claude Code orch, shipped script): `finished seq=203 status=done srv=10356311
  waited=1241s` at 21:35:09; this session made no API call from 21:17:22 to the notice. It
  settled `done`, not `idle`: only a tab in view when the turn ends settles `idle`. Re-runs:
  `finished seq=212 status=done waited=488s` and, with the worker tab focused at arming,
  `finished seq=236 status=done waited=460s` (the stale `idle` at baseline 212 did not count);
  both with zero API calls while waiting. The owner accepted `idle` or `done` and waived a new
  review for that edit.
- 9b (Codex orch, gpt-6.1-sol low, same turn): `finished seq=203 status=done srv=10356311
  waited=1207s` at 21:35:08; 50 API calls while waiting (`exec_command` yields after 1 s, then
  `write_stdin` polls about every 30 s).

## Now

Watcher fix committed on branch `watcher-fix` (f0bcaf0), proof above. Not pushed, merged or
released: the owner decides.

## Next

1. Merge `watcher-fix` to main and release 0.2.0 when the owner says; list the outgoing commits
   and review the full diff before any push.
2. Add a PERMS column to the worker proposal so auto mode lets launches through (owner
   request, 2026-10-24; a PERMS line plus the owner's go got the 9b `danger-full-access` Codex
   launch past auto mode): [perms-column.md](../intent/perms-column.md).
3. Add Command Code as a supported agent (owner's next task, 2026-10-24); scope it with
   `/kis:plan` first.
4. Support several orchs in one project (owner request, 2026-10-24); scope it with `/kis:plan`
   first. Goal and collision points: [multi-orch.md](../intent/multi-orch.md).
5. Re-run the three eval scenarios against the current version to prove the fixes, after the
   owner approves the harness, model and effort.
