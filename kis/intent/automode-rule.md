# Plan: installer offers the auto-mode rule

Date: 2026-10-25. Owner: the user. Mode: Standard. Scope approved 2026-10-25.

## Problem

A Claude Code orch in auto mode cannot launch workers: the classifier blocks `herdr agent start`
with `--dangerously-skip-permissions` or `--yolo` as `[Create Unsafe Agents]`. An
`autoMode.allow` entry in `~/.claude/settings.json` clears it, and an agent cannot add that entry
itself (see [herdr.md](../knowledge/herdr.md), Host launch gates). The owner wants the installer to
offer it. Add nothing unnecessary to the skill or KIS.

## Decisions (owner, 2026-10-25)

- `install` and `update` ask `Add the herdr-orch auto-mode rule to ~/.claude/settings.json?
  [y/N]` on a terminal (read from `/dev/tty`), default No, only when `~/.claude` exists and the
  rule is not already there. The `~/.claude` check runs before the skill install, which creates
  `~/.claude/skills`. Without a terminal they print one line saying how to add it.
  `--claude-automode yes|no` answers without asking.
- A yes backs up `settings.json` beside it, writes the rule to a temp file beside the real path
  (a symlink is resolved, not replaced) and renames it over, then prints the diff. An entry that
  starts with `Herdr worker launches:` or `herdr-orch worker launches:` is replaced by the
  rule; a re-run changes nothing. `"$defaults"` goes first only in an `allow` list the installer creates; an existing
  list is left as it is. Invalid JSON, a top level that is not an object, or an `autoMode` or `allow` of the wrong
  type is an error and the file is untouched.
- Rule text:
  "herdr-orch worker launches: `herdr agent start <name> --kind claude|codex --pane <pane> -- ...`
  with `--dangerously-skip-permissions` (Claude) or `--yolo` (Codex) is allowed after the user
  said go to that worker's proposal. The user runs the herdr-orch skill on purpose: it proposes
  each worker and waits for the user's go, and every worker runs in a visible Herdr tab the user
  and the orch watch."
- `SKILL.md` blocked-launch rule: the second choice becomes re-running the installer with
  `--claude-automode yes` and starting a new Claude session; `Bash(herdr agent start:*)` goes.
- 0.3.0 is unreleased: no version bump.

## Tasks

- [x] 1. `bootstrap.sh`: the question, `--claude-automode yes|no`, the edit (Ruby JSON), the
  usage text.
- [x] 2. `tests/test-install.sh`, temp home only: yes adds the rule with `"$defaults"` and a
  backup, and every other key is unchanged; a re-run changes nothing; the old rule is replaced;
  no leaves the file byte-identical; no terminal (run under `setsid`, so `/dev/tty` cannot open)
  and no flag leaves it untouched and prints the hint; invalid JSON and an `allow` that is not a
  list error and leave it untouched; no `~/.claude` asks nothing and creates nothing; an existing
  `allow` list without `"$defaults"` keeps none. Mutation-check each guard.
- [x] 3. `SKILL.md` blocked-launch rule per the decision.
- [x] 4. `README.md` one sentence under Quick start; `CHANGELOG.md` 0.3.0 line.
- [ ] 5. Owner's live run, when the owner chooses (it installs 0.3.0 over the copy other orchs
  read): `./bootstrap.sh update --source . --claude-automode yes`, then a new Claude session
  launches one haiku worker. Until then it is recorded as not run.
  Status: not run (2026-10-25); waits for the owner.

## Out of scope

Codex config, the `check` command, Bash allow rules, other Next items, pushing or releasing.

## Acceptance

- `tests/run.sh` passes with the new install cases; each guard trips its case when broken.
- `SKILL.md` stays under 500 lines.
- Task 5 passes the classifier with the new rule text, or is marked not run.

## Risks and assumptions

- A new Claude session may be needed to load the rule (untested).
- The classifier is not deterministic; one passing launch is one data point.
- The JSON rewrite reformats the whole file; the printed diff and the backup expose any change.

## Review
- Reviewed: 2026-10-25 by codex gpt-6.1-sol (medium); plan hash 1806f4025458
- [fixed] Wrong JSON types (non-object top level, autoMode, allow) were not rejected - they are now an error with the file untouched, and a test covers a non-list allow
- [fixed] The write was not atomic after the backup - write a temp file beside the resolved real path and rename it over
- [fixed] The skill install creates ~/.claude/skills, so a later ~/.claude check always passes - the check runs before the install
- [fixed] Redirecting stdin still leaves /dev/tty open, so the no-terminal test could prompt - it runs under setsid
- [fixed] Rule matching was loose and unrelated settings were not tested - match the two exact prefixes, and the yes test checks every other key is unchanged
