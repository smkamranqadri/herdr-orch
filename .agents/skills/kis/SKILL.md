---
name: kis
description: Operate KIS project memory under `kis/`, where Knowledge holds stable facts, Intent holds goals and plans, and State holds the current task, blocker, proof, and next action. Use when the repository has a `kis/` directory, when starting or resuming multi-step work or asking where it left off and what is next, when a decision, plan, blocker, proof, or status needs recording, when choosing how much process a task needs, when project memory has gone stale or contradictory, or when a project needs memory set up from scratch. Skip for trivial one-off work and questions the code already answers.
metadata:
  version: "0.11.0"
---

# KIS

KIS is the project's operational memory. Keep it small and synchronized so a fresh agent can recover what the project is, what the user wants, what was decided, what is happening now, and what is next.

```text
kis/
  knowledge/   stable facts: stack, architecture, domain terms, constraints, standards, durable decisions
  intent/      direction: vision, PRDs, plans, acceptance criteria, design direction
  state/       current reality: branch, task, blocker, commands, status, proof, next action
```

If `kis/` does not exist, read [bootstrap.md](references/bootstrap.md).

## Truth Hierarchy

```text
State > Intent > Knowledge > conversation > repository inspection
```

Operational reality overrides stale plans. When sources contradict, fix the single source of truth instead of duplicating the fact.

State should answer the recovery questions, near the top:

```text
What branch?  What task?  What command?  What blocker?  What's next?
```

Keep State lean. Stable facts belong in Knowledge, plans belong in Intent.

When State has a `Run: <description>; live record at <path>` line, an orchestrator is mid-run and the file it names is the live record for task status and the next action: while the run is active, take the current Task and Next from it rather than from State or the conversation, and a path that does not exist is a contradiction to report. State keeps the pointer and one proof line per merged unit of work. KIS steps never copy task status from the live record into State and never remove the `Run:` line: the orchestrator removes it when the run closes, then flushes the run's decisions to Intent.

State carries a `Stamp:` line, written by sync as the helper's output verbatim (run with the project root, no markdown around it), that fingerprints the code outside `kis/`. When the anchor or start reports `Stale State`, the code moved on after the last sync: check State against the repo before trusting Task and Next, and say so in your report.

## Work Modes

Choose one before starting.

| Mode | Use for | Process |
| --- | --- | --- |
| Fast | quick lookup, small config or copy change, obvious bug fix, localized refactor | Load State, inspect only what matters, act, verify, update State only if reality changed. No interview. |
| Standard | multi-file changes, normal feature work, unclear product changes, anything that changes KIS | Run the full loop below. |
| Phase | multi-session work, major refactor, architecture change, migration, deployment | Run the full loop, split into phases, verify each phase. Read [execution.md](references/execution.md). |

When a Fast Mode task turns out to be ambiguous or risky, stop and switch to Standard.

## Operating Loop

```text
LOAD -> QUESTION -> CHALLENGE -> STRUCTURE -> PLAN -> ACT -> SYNCHRONIZE
```

### LOAD

Read `kis/state/*`, then the relevant `kis/intent/*`, then only the required `kis/knowledge/*`. Inspect the repository only where KIS is unclear or looks stale.

Done when: you can answer the recovery questions without reading anything else.

### QUESTION

Interview the user relentlessly until you reach a shared understanding of the work. This is the step that prevents wasted implementation, so do not shortcut it by assuming.

- Ask one question at a time and wait for the answer. Multiple questions at once are bewildering.
- Walk down each branch of the decision tree, resolving dependencies between decisions one by one.
- Give your recommended answer with every question, and say briefly why.
- If a fact can be found in KIS, the filesystem, the repository, or available tools, look it up instead of asking.
- The decisions are the user's. Put each one to them and wait.

Skip the interview only in Fast Mode, and only while the task stays unambiguous and reversible.

Done when: the user confirms the understanding is shared.

### CHALLENGE

Challenge vague ideas, weak requirements, risky assumptions, missing edge cases, scope creep, and approaches heavier than the goal needs. Explain the practical tradeoff and offer a clearer path.

When replicating an existing product, screen, or workflow, study the reference before choosing an architecture.

Done when: every assumption you are relying on has been put to the user.

### STRUCTURE

Done when: every new fact sits in exactly one layer.

### PLAN

Plan only enough to execute safely: scope, acceptance checks, risk, files likely involved, verification method, and whether a specialist or review is needed. For specialist routing, read [specialist-routing.md](references/specialist-routing.md).

A written plan in `kis/intent/` is reviewed before ACT by a different CLI than its author. Propose the harness, model, and effort to the user and get approval first. Record the outcome, or the user's waiver, in the plan's `## Review` section in the format [execution.md](references/execution.md) (Plan Review) owns.

Done when: the user has approved the scope and, for a written plan, `scripts/plan-review.sh check` passes. In Fast Mode, when the verification method is settled.

### ACT

Refuse a written plan whose `scripts/plan-review.sh check` fails. Update State with the current task, mode, status, and verification plan. Then implement only the current scope, avoid unrelated changes, and keep changes reviewable. For written plans and Phase Mode, read [execution.md](references/execution.md).

Done when: proof exists. See Proof Before Done.

### SYNCHRONIZE

Ask whether Knowledge, Intent, or State changed, and update only those files. Record proof in State when it helps recovery. Do not paste implementation history into KIS. For cleanup rules and when to run a consistency sweep, read [file-hygiene.md](references/file-hygiene.md).

Done when: every fact that changed sits in exactly one layer, and nothing left in `kis/` contradicts it.

## Proof Before Done

Never mark a task done from intuition, code inspection, or an agent report. Proof is test, build, lint, or typecheck output, a manual verification result, a screenshot or browser check for visible UI, a deployment check, or a failing reproduction that no longer fails.

```text
Proof:
- npm test - passed
- npm run build - passed
- Manual check: login flow works
```

If verification fails, record it in State as the current blocker instead of marking the task done.

## Commands

Each file in `commands/` is an explicit entry point into one step of this loop: `start` (LOAD), `plan`, `act`, `sync`, `check` (maintenance), and `init` (bootstrap). A command re-enters the loop; it is not a second workflow. For host adapters and the re-anchor layer, read [commands.md](references/commands.md).
