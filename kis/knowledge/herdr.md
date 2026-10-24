# Herdr facts

Verified on Herdr 0.9.5. Re-check after a Herdr upgrade.

- `completion_seq` rises once per finished turn. It is the only reliable turn signal.
- `done` and `idle` both mean the agent is stopped; neither tracks turns, so a `done` can be left
  over from the previous turn.
- `worktree create` has no `--json` flag.
- A Codex orch's default sandbox fails every `herdr` command with `PermissionDenied`; it needs
  `--sandbox danger-full-access`.
