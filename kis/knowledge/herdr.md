# Herdr facts

Verified on Herdr 0.9.5. Re-check after a Herdr upgrade.

- `completion_seq` rises once per finished turn. It is the only reliable turn signal.
- `done` and `idle` both mean the agent is stopped; neither tracks turns, so a `done` can be left
  over from the previous turn.
- `agent wait --until done` never fires on `idle` (a worker whose tab the user viewed settles as
  `idle`), so it only returns at its timeout. `agent wait` with no `--until` matches idle, done or
  blocked, but returns at once (38 ms) when the agent is already stopped; `--until working`
  blocks on a stopped agent (checked 2026-10-24).
- A Herdr server restart resets every `completion_seq` (seen 436 → 26 and 409 → 23 on
  2026-10-24) and breaks a running watcher loop.
- `agent get` omits `completion_seq` while the agent is working and on a freshly started agent
  (seen 2026-10-24); treat a missing value as unknown, not 0.
- A screen read of a Claude pane can show Claude Code's prompt suggestion after `❯`. It is not
  typed input, and typing replaces it.
- `worktree create` has no `--json` flag.
- A Codex orch's default sandbox fails every `herdr` command with `PermissionDenied`; it needs
  `--sandbox danger-full-access`.

## Host launch gates

Checked 2026-10-24 on Claude Code 2.1.300 and Codex 0.162.1.

- Claude Code auto mode blocks `herdr agent start` with `--dangerously-skip-permissions` or
  `--yolo` as `[Create Unsafe Agents]`, a soft block that clears only when the user's own message
  names the agent and the dropped approvals; a PERMS line in the orch's reply does not count. An
  `autoMode.allow` entry in `~/.claude/settings.json` clears it (project settings are ignored for
  `autoMode`), and the agent cannot add that entry itself: the classifier blocks the edit.
- A Codex orch (`--sandbox danger-full-access -a on-request`, `approvals_reviewer = "auto_review"`)
  launches workers with no prompt or review.
- Launched with those flags in a new empty folder, neither Claude nor Codex showed a
  folder-trust prompt.
