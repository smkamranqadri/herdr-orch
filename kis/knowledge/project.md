# Project

herdr-orch is a skill that turns Claude Code or Codex into an orch that coordinates worker agents
over the Herdr CLI. Public repo https://github.com/smkamranqadri/herdr-orch, MIT.

## Origin and credit

It began as an adaptation of an unlicensed skill (herdr-orchestration by Pedro Nauck). The owner
rewrote it as their own under MIT. The only credit is the "Inspired by" line in `README.md`; do
not add credits anywhere else.

## Owner decisions on orch behaviour

Decided with the owner on 2026-10-23/24. Change only with the owner's approval.

- Workers always launch with `--dangerously-skip-permissions` (Claude) and `--yolo` (Codex).
  Kept on purpose.
- The orch proposes every worker (kind, model, effort, tab label, worktree, reason) and waits for
  the owner's go before creating a worktree or launching.
- One writer per checkout; each writer gets its own Herdr worktree.
- Briefs are files under `${TMPDIR:-/tmp}/herdr-orch/<task>/`; workers get a pointer prompt.
- Turns are tracked by `completion_seq`, never by `done`/`idle` (see [herdr.md](herdr.md)).
- The orch never writes product code beyond one-token fixes; an edit outside a worker's claim
  goes back to the owner.
- Manual invocation only (`disable-model-invocation: true`).

## Release conventions

Modelled on the owner's sibling repo `../lore-skill`: `bootstrap.sh` plus
`scripts/install-skill.sh`, README with hero SVG and badges, CHANGELOG, CONTRIBUTING, SECURITY,
MIT LICENSE, GitHub Actions running `tests/run.sh`. Check `../lore-skill` when adding a release
artifact.
