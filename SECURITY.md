# Security

## Reporting a problem

Please report security problems privately through GitHub's
[security advisories](https://github.com/smkamranqadri/herdr-orch/security/advisories/new),
not in a public issue. Expect a first reply within a week.

## What herdr-orch does on your machine

herdr-orch is instructions for a coding agent, not a program. When you invoke it, the agent you
are talking to (the orch) runs `herdr` commands that:

- create tabs and Git worktrees in your Herdr workspace,
- start Claude Code or Codex workers in those tabs, and
- send them prompts and read their screens.

**Workers launch with their permission prompts turned off**: Claude Code with
`--dangerously-skip-permissions` and Codex with `--yolo`. A worker can therefore run any command
and edit any file its user account can reach, without asking. Run herdr-orch only on code and
machines where that is acceptable to you.

## Safeguards

- The orch proposes every worker and waits for your go before it creates a worktree or launches
  anything.
- Every worker that edits files gets its own worktree; the orch never puts two writers in one
  checkout.
- The orch does not write product code itself, beyond one-token fixes after reading a diff, and
  it asks you before accepting an edit outside a worker's claim.
- Packets are written to `${TMPDIR:-/tmp}/herdr-orch/`, outside your repo.
- The installer copies only `skills/herdr-orch/` and never overwrites a path you own.
