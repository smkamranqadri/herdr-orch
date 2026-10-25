# Current

Stamp: command-code 3c9b91e 4863a32817ab

Status: 0.4.0 on main, unreleased: plan-first delegation removed (ec2be79) and Command Code
as a worker kind (2026-10-25), installed in ~/.agents/skills from the branch by the owner.
0.3.0 released 2026-10-25 (tag `v0.3.0` at 6f3b551). 0.2.0 is tagged `v0.2.0` at d604944,
0.1.0 `v0.1.0` at 6fcd718.

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
- Codex orch trust-prompt run, 2026-10-25 (folders under `~/herdr-trust-test-20261025/`,
  outside `/tmp`, which `~/.claude.json` trusts and so hides Claude's prompt): the first Codex
  orch launch printed `Killed` right after start (cause unknown: no OOM in the journal, no Codex
  log rows); one fresh relaunch worked. No Codex trust prompt with explicit flags. The Codex
  orch launched `orch2-claude` with no approval prompt; `agent start` returned `agent_not_ready`
  on Claude's prompt: "Accessing workspace: <folder> ... Quick safety check: Is this a project
  you created or one you trust? ..." with options `❯ No, exit` (default) and `Yes, I trust this
  folder`, "Enter to confirm · Esc to cancel". The orch followed 0.3.0 and sent `enter`, which
  chose "No, exit": Claude quit and no reply came. Bug in the shipped rule: the default is not
  the trust option. Watcher: `finished seq=430 status=done waited=50s`. Both tabs closed.
- Trust-key fix, 2026-10-25, Claude Code 2.1.300, Herdr 0.9.5 (server restarted mid-test,
  marker 10356311 to 10769305, which ended the first try after trust was saved): in a new folder
  `worker3`, `agent start` returned `agent_not_ready`; `send-keys down` moved `❯` to "Yes, I
  trust this folder" (seen on a second read; the first read came too soon); `enter`; the worker
  replied `ok` (`finished seq=19 status=done waited=5s`). SKILL.md now says down, check, enter.
  `tests/run.sh` exit 0. Tab closed.
- Auto-mode installer, 2026-10-25 (2fb7b08): `tests/run.sh` exit 0 (install cases 8-16);
  12/12 guard mutations tripped their case, restores byte-identical
  (`$TMPDIR/automode-mutations.log`, scratchpad); a pty run asked `[y/N]`, `y` added the rule,
  `n` and Enter skipped; on a copy of the owner's settings the diff was one line (old rule to
  new). Owner's live run, 2026-10-25: `bootstrap.sh update --source . --claude-automode yes`
  installed 0.3.0 and swapped the old rule for the new one (one-line diff, backup kept);
  `bootstrap.sh check` current; `claude auto-mode config` shows one herdr rule, the new text.
  From this orch session, `herdr agent start rule-check` (haiku low,
  `--dangerously-skip-permissions`) passed auto mode on the first try and replied `ok`. Not
  tested from a new Claude session.
- Multi-orch rules, 2026-10-25: `tests/run.sh` exit 0 (test-skill checked Herdr 0.9.5);
  SKILL.md 403 lines; no unprefixed `fix-loops`/`audit-auth` in SKILL.md; the brief path appears
  only as `herdr-orch/<orch-id>/`; in a throwaway repo `git merge-tree --write-tree main <branch>`
  exited 0 on a clean merge and 1 on a conflict. No live run with two orchs (out of scope).
- Release 0.3.0, 2026-10-25: `tests/run.sh` exit 0 on 6f3b551; CI run 40136527746 passed on
  6f3b551; `bootstrap.sh update --ref v0.3.0` installed it (auto-mode rule already present) and
  `bootstrap.sh check --ref v0.3.0` reports current.
- Plan-mode removal, 2026-10-25: `tests/run.sh` exit 0; `grep -riE 'plan-first|plan
  mode|plan-mode|permission-mode plan'` over skills/, README, AGENTS, CONTRIBUTING and tests/
  finds nothing; `skills/herdr-orch/references/` is gone; SKILL.md 384 lines.
- Command Code tasks 1-3, 2026-10-25 (branch `command-code`, 3c9b91e): `tests/run.sh` exit 0;
  dropping `--yolo ...` from the rule's cmd launch tripped "automode yes wrote the wrong
  settings", restore byte-identical; SKILL.md 409 lines. Live run, 2026-10-25, after the owner's
  `bootstrap.sh update --source . --claude-automode yes` (`claude auto-mode config`: one herdr
  rule, names the cmd launch): `herdr pane run ... cmd -t --yolo -m deepseek/deepseek-v4-flash`
  passed auto mode; `--effort low` exited ("Unknown effort... Supported: off, high, max"), the
  owner chose the default; detected as `cmd` in 10 s, renamed `cc-live`; turn 1 "reply ok" ->
  `ok`, seq 45 (watcher errored on a bad read, see Next); turn 2 "reply ok2" -> `ok2`,
  `finished seq=49 status=done waited=14s`. Tab closed. SKILL.md 411 lines, `tests/run.sh` exit 0.
- 0.2.1, 2026-10-24: `tests/run.sh` exit 0 (wait-turn 30 cases); breaking the seq-rise branch
  fails the new baseline-0 case on its own; restore byte-identical.

## Now

No task in progress.

## Next

1. Watcher dies on one unparseable `herdr agent get` read (2026-10-25: armed right after
   `agent rename` on a Command Code pane, it printed `error unparseable output from herdr agent
   get` and exited 1; the same read parsed a moment later). It should retry a bad read before
   giving up. Scope it with `/kis:plan` first.
2. Run the four eval scenarios: plan approved and reviewed 2026-10-25 (codex gpt-6.1-sol low,
   2 fixed):
   [eval-run.md](../intent/eval-run.md). Ready for `/kis:act`.
