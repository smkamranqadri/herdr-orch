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
