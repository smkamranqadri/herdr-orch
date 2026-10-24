# Current

Stamp: main a12f7bf d958d0792b51

Status: 0.3.0 (launch gates) on main, not pushed or released: merged 2026-10-24 at 370d69c;
the PERMS column was reverted on 2026-10-25 at a12f7bf at the owner's request (the classifier
ignores it). 0.2.1 (baseline wording fix) also unreleased.
0.2.0 released 2026-10-24 (tag `v0.2.0` at d604944, GitHub release "herdr-orch 0.2.0:
event-mode worker watcher") and installed in ~/.agents/skills. 0.1.0 is tagged `v0.1.0` at
6fcd718 (no GitHub release).

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
- Release 0.2.0, 2026-10-24: CI run 40116400195 passed on d604944; `bootstrap.sh update`
  installed 0.2.0; the installed `SKILL.md` and `wait-turn.sh` match GitHub `v0.2.0` byte for
  byte; the installed script printed `gone srv=10356311` for an unknown agent at 22:31.

- PERMS live run (task 5), 2026-10-24, Claude Code 2.1.300 orch, Codex 0.162.1, Herdr 0.9.5:
  after the owner's bare "go" on two PERMS lines, `herdr agent start perms-claude` (haiku low,
  `--dangerously-skip-permissions`) was blocked by auto mode, `[Create Unsafe Agents]`, not
  retried. That rule is a soft block that clears only when the user's own message names the
  agent and the dropped approvals (`claude auto-mode defaults --label 'Create Unsafe'`), so a
  PERMS line in the orch's reply does not clear it. The owner then added an `autoMode.allow`
  rule for herdr-orch worker launches to `~/.claude/settings.json` (throwaway script, backup
  `settings.json.bak-automode-20261024-234420`); after that both launches passed on the first
  try: perms-claude replied `ok` (seq 389, "bypass permissions on"), perms-codex (gpt-6.1-sol
  low, `--yolo`) replied `ok` (seq 394, "permissions: YOLO mode"). Neither showed a folder-trust
  prompt in a new empty folder under the scratchpad. Both tabs closed; `agent list` shows no
  `perms-` worker. Before commit: `tests/run.sh` exit 0, SKILL.md 387 lines. PERMS revert,
  2026-10-25: `tests/run.sh` exit 0; "Propose workers" and eval 1 match c347c1c exactly.
- Codex orch launch gate, 2026-10-24: a Codex 0.162.1 orch (gpt-6.1-sol low, `--sandbox
  danger-full-access -a on-request`, config `approvals_reviewer = "auto_review"`) reading the
  branch SKILL.md proposed `orch-test-claude` with its PERMS line; on the owner's relayed go
  it ran `herdr tab create` and `herdr agent start ... --dangerously-skip-permissions` with no
  approval prompt or review (screen shows `Ran`); the worker replied `ok` (seq 402); the orch
  closed its tab. Watcher: `finished seq=403 status=done waited=35s`. No folder-trust prompt
  for the orch either. Codex orchs are not gated; the block is Claude Code auto mode only.
- 0.2.1, 2026-10-24: `tests/run.sh` exit 0 (wait-turn 30 cases); breaking the seq-rise branch
  fails the new baseline-0 case on its own; restore byte-identical.

## Now

No task in progress.

## Next

1. Auto-mode rule for Claude orchs (owner request, 2026-10-24): `bootstrap.sh` install asks
   the owner whether to add the herdr-orch `autoMode.allow` rule to `~/.claude/settings.json`
   (backup, keep `"$defaults"`, safe to re-run, show the diff), and `SKILL.md`'s blocked-launch
   rule offers that rule. A proposal line naming the flags does not clear the block (see Proof);
   the rule text written into the owner's settings says the orch proposes each worker "with its
   permission flags", which no longer holds since the PERMS revert, so reword it. Scope it with
   `/kis:plan` first.
2. Add Command Code as a supported agent (owner's next task, 2026-10-24); scope it with
   `/kis:plan` first.
3. Support several orchs in one project (owner request, 2026-10-24); scope it with `/kis:plan`
   first. Goal and collision points: [multi-orch.md](../intent/multi-orch.md).
4. Run the four eval scenarios (scenario 4 `idle-finish` is new in 0.2.0) against the current
   version to prove the fixes, after the owner approves the harness, model and effort.
