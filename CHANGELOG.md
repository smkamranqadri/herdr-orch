# Changelog

## 0.1.0

First release.

- One orch session coordinates Claude Code and Codex workers over the Herdr CLI, one named tab
  per worker.
- The orch proposes each worker (kind, model, effort, tab label, worktree, reason) and waits for
  the owner's go before it creates a worktree or launches anything.
- Every worker that edits files gets its own Herdr worktree; read-only workers share the orch's
  checkout. Never two writers in one checkout.
- Packets are files under `${TMPDIR:-/tmp}/herdr-orch/<task>/`; workers get a short pointer,
  at launch and for every follow-up.
- A turn counts as finished only once the worker's `completion_seq` has risen past the value
  recorded before the prompt, so a `done` left over from the last turn is never read as new.
- The orch never writes product code beyond one-token fixes; an edit outside a worker's claim
  goes back to the owner to accept, send back or reject.
- Preflight notes that a Codex orch needs access to the Herdr socket.
- `bootstrap.sh` installs, checks and updates the skill; `evals/` holds three scenarios and a
  sandbox builder.
