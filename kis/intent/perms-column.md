# PERMS column in the worker proposal

Owner request, 2026-10-24. A Standard-mode change to `skills/herdr-orch/SKILL.md`. Untested.

## Problem

An orch in Claude Code auto mode cannot launch a worker: the auto-mode classifier blocks by
default "launching an autonomous agent loop that runs without human approval or a sandbox, such
as one started with `--dangerously-skip-permissions`", and it blocked a Codex `--yolo` launch
(a Codex worker in another Herdr session, 2026-10-24). Per the Claude Code permission-modes docs (read
2026-10-24), an approval in conversation clears a block only when it names the action and what
makes it dangerous, and it covers one action. The owner's "go" on the proposal names neither.

## Change

- Add a `PERMS` column to the "Propose workers" line, e.g. `--yolo (no approvals, no sandbox)`
  or `--dangerously-skip-permissions (no approvals)`, so the owner's go names the danger.
- Say that one go covers each launch shown, and that a blocked launch goes back to the owner
  rather than being retried.
- Never change a worker's permission flags (for example to `--permission-mode acceptEdits`)
  without the owner naming that choice. On 2026-10-24 another orch read a bare "go"
  after a three-option menu as option 2, and the worker then stalled on approvals.
- Launch gate: a folder the TUI has not seen makes it ask first, so `agent start` returns
  `agent_not_ready`. Claude asks "Is this a project you trust?"; Codex asks "Trust this
  folder?" with "1. Trust and continue" (both seen 2026-10-24). Owner decision (2026-10-24): the
  orch answers the trust prompt itself, for the folder it launched the worker in, and does not
  hand it to the owner. The skill says so.
- Mention the alternative the owner can choose: an allow rule `Bash(herdr agent start:*)`, which
  skips the classifier but pre-approves every launch with any flags.

The launch flags stay as decided in [project.md](../knowledge/project.md).

## Proof needed

In auto mode, an orch proposes a `--yolo` worker with the PERMS column, the owner answers "go",
and the launch passes the classifier without a block.
