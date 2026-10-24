# Multi-orch support

Owner request, 2026-10-24. Not planned yet: scope it with `/kis:plan` before any change.

## Goal

Several orch sessions can run at once in the same project (same repo, the same Herdr server,
possibly the same workspace) without colliding. Today `SKILL.md` assumes a single orch and
says nothing about other orchs.

## Collision points found (2026-10-24, against SKILL.md 0.1.0)

- Agent names must be unique across the whole Herdr server: two orchs can both pick `fix-loops`.
- Brief paths `${TMPDIR:-/tmp}/herdr-orch/<task>/` collide when two orchs use the same task slug.
- Worktree branches from `herdr worktree create --branch <slug>` collide on the same slug.
- Every orch integrates into the main checkout, so two orchs merging at once means two writers
  in one checkout. The skill forbids that for workers but not for orchs.
- File claims are checked per orch, so two orchs can hand the same file to two workers.
- Orchs sharing a workspace see each other's tabs, and no rule limits an orch to the tabs it
  created.

## Directions to weigh in the plan

- An orch id, used to prefix agent names, branches and brief paths.
- A rule that an orch acts only on the tabs, panes and worktrees it created.
- A shared claim or merge lock in the repo that every orch checks.
