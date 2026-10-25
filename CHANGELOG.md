# Changelog

## 0.4.0

- Follow-ups are sent with `agent prompt` and tracked with `wait-turn.sh`, not `--wait`: the
  old example led orchs in both hosts to skip the watcher (eval 4, 2026-10-25).
- Proposal lines are printed as plain text, never in a question dialog.
- `SKILL.md` quotes Codex's folder-trust prompt and answers it with Enter for the launch folder.
- `wait-turn.sh` retries an unparseable `herdr agent get` read up to 3 times, 1 s apart, before
  `error`; a Herdr error code is still reported at once.
- Command Code (`cmd`) is a third worker kind: started bare with `herdr pane run`, named with
  `herdr agent rename`, and sent every turn with `herdr pane send-text`. The installer's
  auto-mode rule also allows that launch; re-run `bootstrap.sh update --claude-automode yes`.
- Removed: plan-first delegation (`references/plan-mode.md` and its `SKILL.md` section). Plan
  before delegating; workers run direct.

## 0.3.0

- Several orchs can share a project: each picks an unused orch id that prefixes its agent
  names, worktree branches and brief folder, acts only on what its registry holds, and before
  integrating checks the main checkout is clean and trial-merges the worker branch with
  `git merge-tree`.
- `bootstrap.sh` `install` and `update` ask whether to add an `autoMode.allow` rule to
  `~/.claude/settings.json` that lets a Claude Code orch in auto mode launch workers
  (`--claude-automode yes|no` answers without asking). A yes keeps a backup and prints the diff.
- `SKILL.md` "Launch workers": a launch the host blocks is not retried or reworked; the orch
  offers the owner the exact command or the installer's auto-mode rule and waits. The
  orch never changes a worker's permission flags unless the owner names that choice.
- On `agent_not_ready`, the orch answers Claude's folder-trust prompt itself when it names the
  worker's recorded launch folder, moving to "Yes, I trust this folder" first (the default is
  "No, exit"); any other dialog goes to the owner. A worker whose name did not stick
  is addressed by its pane id.

## 0.2.1

- `SKILL.md`: with no recorded `completion_seq`, start the watcher with baseline `auto`, never
  `0`. A stopped worker that has run turns reads as finished at once against `0`.

## 0.2.0

- Workers are tracked with `scripts/wait-turn.sh`, a shipped watcher the orch runs once per turn
  as a background job. It waits on Herdr's own events and prints one line only when the turn
  ends or something needs the orch (`finished`, `blocked`, `stalled`, `gone`, `restarted`,
  `backstop`, `error`), so a long worker turn costs the orch no turns while it waits. It replaces
  the `--until done` check-ins, which missed workers that settled as `idle` and woke the orch
  every few minutes.
- A finish counts when `completion_seq` rises past the baseline, or when the worker was seen
  working and has settled, so a missing `completion_seq` no longer hides a finished turn.
- A Herdr server restart is detected by the server socket's inode and reported, not read as a
  finished turn.
- New eval scenario 4, `idle-finish`: a worker whose tab the owner viewed settles as `idle`.
- `SKILL.md` notes that text after `❯` in a Claude pane can be a prompt suggestion, and warns
  against `pkill -f` patterns that match the orch's own command line.

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
