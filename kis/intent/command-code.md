# Plan: Command Code as a worker kind

Date: 2026-10-25. Owner: the user. Mode: Standard. Scope approved 2026-10-25.

## Problem

The orch launches only Claude Code and Codex workers. The owner wants Command Code (`cmd`) as a
third worker kind. Herdr 0.9.5 has no Command Code kind for `agent start` and no integration in
`integration status`. Probe on 2026-10-25 (Command Code 1.82.5, no model call): `cmd -t` in a
pane is detected as agent `cmd`, status `idle`, no `completion_seq`; `herdr agent rename <pane>
<name>` names it; on start it writes `.commandcode/taste/taste.md` into its folder. Lore says
`agent prompt` does not reach it and only `pane send-text` does. Add nothing unnecessary to the
skill or KIS.

## Decisions (owner, 2026-10-25)

- `cmd` is a third worker kind, used like claude and codex: launched bare in its tab's root pane
  with `herdr pane run <pane_id> "cmd -t --yolo -m <model> --effort <effort>"`; ready when
  `herdr agent get <pane_id>` shows agent `cmd`; then `herdr agent rename <pane_id>
  <agent-name>`, the watcher armed, and every turn, the first included, sent as literal text
  with `herdr pane send-text` and Enter (no pointer in the shell line). Tracked with
  `wait-turn.sh`. The existing `agent start`, ready-on-success and `agent prompt` rules are
  scoped to claude and codex. No plan-first and no Command Code orch.
- The installer's auto-mode rule also allows that `herdr pane run ... cmd -t --yolo ...`
  launch after the user's go. It keeps the `herdr-orch worker launches:` prefix, so the
  installer replaces the old rule; the owner re-runs `bootstrap.sh update --claude-automode yes`.
- One line in `SKILL.md`: Command Code with `--yolo` can reach outside its folder, so pick claude
  or codex for slices that need tight confinement.
- One line in `SKILL.md`: `.commandcode/` is Command Code's own state; the worker never commits
  it and the orch does not count it against the claim.
- Preflight exempts `cmd` from the `integration status` check.
- Version 0.4.0.

## Tasks

- [x] 1. `SKILL.md`: the kind, launch, readiness, rename and send text; the claude/codex scoping
  of the existing launch and prompt rules; the preflight exemption; the two lines above.
- [x] 2. `bootstrap.sh` rule text; `tests/test-install.sh` asserts the rule names the `cmd`
  launch; break it and watch that case fail.
- [x] 3. `README.md` requirements line adds "(Command Code for workers)"; `CHANGELOG.md` 0.4.0;
  `metadata.version` 0.4.0.
- [ ] 4. Live run from this Claude Code orch session in auto mode, after the owner runs
  `./bootstrap.sh update --source . --claude-automode yes`: one throwaway worker,
  `deepseek/deepseek-v4-flash` low, a new empty folder under the scratchpad. Launch bare, rename,
  arm the watcher, then send "reply ok"; record whether auto mode passed the launch, the
  watcher line and whether `completion_seq` rose. Arm again, send "reply ok2", record its
  watcher line and reply. A backstop with no `working` seen is recorded as a missed transition,
  not as a pass. Retire it.
- [ ] 5. Make `SKILL.md` match task 4: if tracking or the follow-up failed, say what fails
  instead of claiming it.

## Out of scope

Plan-first for `cmd`, a Command Code orch, `.gitignore` or `.git/info/exclude` edits, the other
Next items, pushing or releasing.

## Acceptance

- `tests/run.sh` passes; `test-skill.sh` confirms every Herdr command the new text names.
- `SKILL.md` stays under 500 lines.
- Task 4: the launch passes auto mode, two turns are tracked and both replies seen; or `SKILL.md`
  records what failed.

## Risks and assumptions

- Whether `completion_seq` rises for `cmd` is unknown; the watcher's seen-working-then-settled
  path may carry it.
- One live run is one data point; Command Code changes between versions (1.82.5 probed).

## Review
- Reviewed: 2026-10-25 by codex gpt-6.1-sol (medium); plan hash d83fdeaf1f60
- [fixed] Task 4 did not name the auto-mode orch context, so a pass would not prove the rule - the run is from this Claude Code orch session in auto mode
- [fixed] Without completion_seq a fast first turn could finish before the watcher is armed - launch bare, rename, arm the watcher, then send each turn; a backstop with no working seen is a missed transition
- [fixed] The pointer in the launch line crossed two shells and could break on $, backticks or an apostrophe - turns go through pane send-text as literal text, nothing in the shell line
- [fixed] Existing launch, readiness and prompt rules read as universal - scoped to claude and codex, with cmd readiness defined as agent get showing agent cmd
