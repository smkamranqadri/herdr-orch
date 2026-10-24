---
description: Recover project context from KIS, report current reality, and pick a work mode.
argument-hint: [optional task or focus]
---

# KIS Start

Run the LOAD step of the KIS loop, then stop for confirmation. Do not implement anything in this command.

KIS is this project's operational memory under `kis/`:

```text
Knowledge = stable facts and rules
Intent    = goals, plans, acceptance criteria
State     = current operational reality
```

Full instructions: `.agents/skills/kis/SKILL.md`.

## Steps

1. If `kis/` does not exist, stop and tell the user to run the init command instead.
2. Read `kis/state/*` first.
3. If State has a `Run:` line, read the head (about 60 lines) of the live record it names and take Task and Next from there. Say "run active, live record at <path>" in the report. If that path does not exist, report it as a contradiction.
4. Read only the `kis/intent/*` relevant to `$ARGUMENTS` or to the current State task.
5. Read only the `kis/knowledge/*` needed to act.
6. Inspect the repository only where State or Intent is unclear or looks stale. If the anchor printed a `Stale State` line (or `.agents/skills/kis/scripts/state-stamp.sh --check` prints one), the code changed after the last sync: inspect the repo before trusting Task and Next, and say so in the report.
7. Resolve contradictions with the truth hierarchy: State, then Intent, then Knowledge, then conversation, then repository inspection.

## Report

```text
Branch:
Task:
Mode:
Command:
Blocker:
Proof on record:
Next:
```

Then add:

- anything in KIS that contradicts the repository
- anything in State that is stale and should move to Knowledge or Intent
- the smallest work mode that fits the next action (Fast, Standard, or Phase)

## Stop Condition

End with the proposed work mode and next action. Wait for the user to confirm or redirect before planning or implementing.
