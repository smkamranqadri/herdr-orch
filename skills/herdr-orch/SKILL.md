---
name: herdr-orch
description: "Coordinates Claude Code and Codex worker agents from one orch session over the Herdr CLI, one named tab per worker: launch, prompt, track turns, verify and retire. Use when the user asks to delegate work to Herdr workers or run several agents through Herdr."
disable-model-invocation: true
metadata:
  author: smkamranqadri
  version: "0.1.0"
---

# herdr-orch

The top-level agent is the **orch** (Codex, Claude, Fable, or another); it
delegates to **worker** TUIs that gather evidence, draft bounded patches, run
tests, and report. The orch owns assignment, state, conflict control,
verification, integration, and the final user-facing answer. It never writes
product code; after reading a worker's diff it may fix one-token mechanics (a
typo, an import, a version pin) itself. Herdr is the substrate: each worker TUI
owns a named tab, and the socket CLI (`herdr …`) gives the orch placement,
input, screen reads, and native agent-status waits.

## One worker, one named tab

Every worker gets its own tab, labeled at creation with `tab create --label`.
The tab bar is the orch's dashboard: a labeled tab says which model is running
which slice, and stays readable no matter how many workers are live.

Tabs also cost no screen area. A split pane divides the caller's screen with
every worker, and on a laptop the third worker leaves every pane too narrow to
read. Split a pane only when the user explicitly asks to watch a worker beside
the caller.

Two names per worker, both required at launch:

- **tab label** — `<model>: <slice>`, e.g. `opus: fix loops`, `codex: audit
  auth`. Free text; keep it short, tab bars truncate.
- **agent name** — the slice as a slug, e.g. `fix-loops`. Must match
  `[a-z][a-z0-9_-]{0,31}` and be unique among live agents. Every `agent …` verb
  accepts it in place of a pane id.

## Workers are TUIs — no headless runners

A worker is an interactive TUI — `claude` or `codex` — started with `herdr agent
start`, which validates the agent's identity and returns only once Herdr sees it
ready for input. Herdr's agent-state integrations hook those TUIs, so `agent
wait`, `agent list`, and blocked/done detection exist only while a real TUI is
on screen.

Headless runners — `claude -p`, `codex exec`, anything that streams JSON events
into a pane — never report state, so waits never fire and the delegation dies
silently. A worker tab filling with raw JSON event lines is a broken delegation:
interrupt it (`herdr pane send-keys <pane_id> ctrl+c`) and relaunch through
`agent start`.

## Invariants

- Scope every action to the caller workspace unless the user names another
  target.
- Resolve caller context from `HERDR_WORKSPACE_ID`, `HERDR_TAB_ID`, and
  `HERDR_PANE_ID` (injected into every Herdr pane) before any focused-window
  fallback.
- Address workers by ids parsed from command JSON — agent name for `agent …`
  verbs, `w2:t3` / `w2:p4` for tab and pane verbs — never by guessed position.
- Pass `--no-focus` on every creating verb (`tab create`, `workspace create`,
  `worktree create`, `pane split`); use focus verbs only when the user asks.
- Retire every worker you launch when its assignment and planned integration
  follow-ups are finished (see Retire workers).

## Workflow

Copy this checklist into the registry and tick it off:

```text
- [ ] Preflight
- [ ] Delegation packets: one file per worker
- [ ] Propose workers; wait for the owner's go
- [ ] Worktree isolation: one worktree per writer, after the go
- [ ] Launch workers; record each completion_seq
- [ ] Track workers until finished or blocked
- [ ] Verify worker output and the diff
- [ ] Retire workers
```

## Preflight

Inspect the daemon, integrations, and caller context:

```bash
herdr status                 # server running + socket path
herdr integration status     # selected worker runtime must show `current`
herdr pane current --current # caller pane / tab / workspace ids
herdr agent list             # agents already running
```

Check/install only the integration for each selected runtime. Reuse this
preflight in the same workspace while the daemon and integrations are unchanged;
a new packet alone does not require repeating it.

A Codex orch needs access to the Herdr socket: its default sandbox fails every
`herdr` command with `PermissionDenied`. If `herdr status` fails that way, stop
and ask the owner to restart the orch with `--sandbox danger-full-access`.

## Delegation packets

Write each packet to a file,
`${TMPDIR:-/tmp}/herdr-orch/<task>/<agent-name>.md`, and send the worker only a
pointer: `The user asked for this: read <packet path> in full and follow it.`
For a follow-up, update the packet file and point at the changed part. Each
packet is a standalone contract. Include:

- repo path and exact objective
- worker role and model
- execution mode: direct (default) or plan-first (user-activated)
- files, packages, or surfaces in scope
- files and behaviors explicitly out of scope
- claimed files or work slice, to avoid conflicts
- dependencies and the current interface/contract the worker can rely on
- expected evidence needed for this claim: changed files, commands with results
  and checked inputs, relevant artifacts, and remaining uncertainty
- verification ownership: worker checks, orch integration checks, and any final
  delivery checks owned by the enclosing workflow
- stop conditions: unexpected code shape, repeated command failure, auth/model
  blocker, or need for out-of-scope edits

Assign coherent outcomes that can proceed independently. If a consumer depends
on an unsettled interface, resolve that interface first or keep producer and
consumer under one owner. File count alone is not a reason to split work. Tell
each writer it owns its checkout, that other workers run in separate worktrees,
and that it must report interface changes before dependent work proceeds. Reuse
the same worker for related integration fixes; send the changed contract and
remaining work instead of a fresh discovery assignment.

## Propose workers

Before launching, print one line per worker and wait for the owner's go:

```text
NAME | KIND | MODEL | EFFORT | TAB LABEL | WORKTREE yes/no | reason
fix-loops | claude | opus | high | "opus: fix loops" | yes | touches retry core
audit-auth | codex | <model> | medium | "codex: audit auth" | no | read-only review
```

Choose model and effort by the slice's difficulty and say why in `reason`. One
go covers the lines shown; a new or changed worker needs a new go.

## Worktree isolation

Every worker that edits files gets its own worktree; read-only workers (review,
audit, explore) run in the orch's checkout. Never put two writers in one
checkout. Create worktrees only after the owner's go. Herdr manages worktrees
natively, each as its own labeled workspace:

```bash
herdr worktree create --workspace "$HERDR_WORKSPACE_ID" \
  --branch <slug> --label "<slug>" --no-focus
```

Create the worker's tab inside that workspace (`tab create --workspace
<worktree_workspace_id>`) so its cwd is the isolated checkout.

## Launch workers

Launch with the approved model and effort. Launch is two commands: create the
named tab, then start the TUI in that tab's root pane.

```bash
# 1. named tab — returns .result.tab.tab_id and .result.root_pane.pane_id
herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd "$PWD" \
  --label "opus: fix loops" --no-focus

# 2. worker TUI in that tab's root pane; native flags follow `--`
herdr agent start fix-loops --kind claude --pane <root_pane_id> -- \
  --model opus --effort high --dangerously-skip-permissions "<pointer>"

herdr agent start audit-auth --kind codex --pane <root_pane_id> -- \
  -m <model> -c model_reasoning_effort=medium --yolo
```

Capture `tab_id`, `pane_id`, and the agent name in the registry — retiring and
screen reads need all three.

Claude always launches with `--dangerously-skip-permissions` and Codex with
`--yolo` — workers run unattended and must not stall on permission prompts.
Plan-first runs add Claude's `--permission-mode plan`; the flags compose (see
Plan-first delegation).

`agent start` returns success only after Herdr detects the agent ready, so a
non-zero exit is the launch failure — read the tab's root pane (`herdr pane read
<pane_id> --source visible`) before retrying. Confirm the label stuck with
`herdr tab list --workspace "$HERDR_WORKSPACE_ID"`; if the tab shows a default
label, restore it:

```bash
herdr tab rename <tab_id> "opus: fix loops"
```

## Sending prompts to running TUIs

Prefer passing the packet pointer (see Delegation packets) as launch argv — the
session starts working immediately and skips the TUI-ready race. Exception:
Codex plan-first launches bare (see Plan-first delegation).

For any follow-up, use `agent prompt` — it submits text plus Enter atomically,
honoring the pane's live bracketed-paste mode, and `--wait` blocks until the
worker settles:

```bash
herdr agent prompt fix-loops \
  "The user asked for this: read <packet path> §Follow-up 2 and follow it." \
  --wait --timeout 300000
```

A trailing `\n` in `pane send-text` does not submit — a TUI renders it as a soft
newline and the prompt sits unsubmitted. An unconfirmed send is not delivered:
if `--wait` returns `agent_prompt_stalled`, the worker never changed state —
read the screen and resend.

## Plan-first delegation (opt-in)

Plan-first runs only when the user activates it — an explicit ask ("plan first",
"plan mode") or a `--plan-mode` flag on the invocation. The default delegation
is direct: launch and run hands-off. Investigation complexity alone does not add
a planning approval step.

Once activated, the worker plans, the orch reviews and accepts, then it runs
hands-off. The launch flags, shift+tab sequences, status checks, and acceptance
menus are exact and differ per TUI. **Read
[references/plan-mode.md](references/plan-mode.md) in full before launching a
plan-first worker.**

## Track workers

Orchestrations are long-running — worker slices take minutes to hours, and a
worker is never abandoned because a wait expired. Block on Herdr's native agent
status in **check-in intervals** of 3–5 minutes (sized to the slice — longer for
heavier slices) instead of polling screens:

```bash
herdr agent wait fix-loops --until done --timeout 300000     # completion check-in
herdr agent wait fix-loops --until blocked --timeout 300000  # question or menu
herdr pane wait-output <pane_id> --match "<text>" --timeout 300000
```

Orch reads never mark a tab seen, so an unfocused worker settles as `done`, not
`idle` — but a tab the user has viewed settles as `idle`, and both mean stopped.
Neither status tracks turns: a worker still `done` from its last turn matches a
wait at once, and `agent prompt --wait` can match a turn that was already
running. Before each prompt, record the worker's `completion_seq` from `herdr
agent get <name>`; count the turn finished only once `completion_seq` has risen
past that value, and re-enter the wait if it has not. `--timeout` is the
check-in interval, never a deadline on the worker. On expiry, read the screen
(`herdr agent read fix-loops --source recent-unwrapped --lines 120`) and
re-enter the wait — loop until the worker reaches a terminal state, asks a
question, or a stop condition fires. When a reported status looks wrong, debug
detection with `herdr agent explain <pane_id> --json`.

Maintain a compact registry in the existing task notes or handoff: orch
identity; worker agent name, tab label, role, model; workspace/tab/pane ids;
objective sent and start time; status (starting, planning, plan-review,
plan-accepted, running, blocked, reported, verified, retired); claimed files or
work slice; worker-reported commands and results; orch verification performed;
final disposition (accepted, rejected, superseded, or blocked).

Keep the tab label current as a slice changes, and announce milestones without
stealing focus:

```bash
herdr tab rename <tab_id> "opus: fix loops (verifying)"
herdr notification show "Workers done" --body "2/2 verified" --sound done
```

## Verify worker output

Treat worker output as untrusted until verified. Monitor and verify without
changing focus:

- Read worker tabs read-only (`agent read <name> --source recent-unwrapped
  --lines 200`); ask a worker for a concise status summary when output is
  unclear.
- Re-open cited files locally to verify high-impact findings. For visual output,
  open the delivered images and their named visual references side by side; file
  counts, dimensions, and a worker's verdict do not establish visual fit. Check
  one representative image before expanding an expensive generation batch.
- Inspect command results, exit status, checked inputs, and evidence paths.
  Reuse trustworthy worker evidence for unchanged inputs; rerun missing, stale,
  contradictory, or unverifiable checks. The orch runs integration checks the
  worker did not cover, plus any checks required by project policy. A worker
  handoff alone does not invalidate evidence or require a second full suite.
- Review the final diff before accepting any worker patch.
- If a worker edits outside its claim, pause integration and ask the owner to
  choose: accept, send the cleanup back to that worker, or reject the patch.
  Recommend one.

When `--lines` stops revealing more of a completed response, the TUI is on the
terminal's alternate screen and those rows are gone. Ask the worker to write its
full report as Markdown in a temp directory and reply with the path, then read
the file.

## Retire workers

A delegation ends with the worker retired — tab closed. Keep a reported worker
available while reviewing or integrating its outcome when related follow-ups are
expected. Retire it once the disposition is recorded and that work is done:

```bash
herdr tab close <tab_id>
```

Closing the tab ends the TUI session and its scrollback, so record what the
registry needs first — report text, cited line refs, command output. Files,
diffs, and worktrees survive on disk.

A worker stays open while mid-run, blocked, awaiting planned integration
follow-ups, while its screen is evidence for an unresolved failure, or when the
user asks to inspect it — record the reason in the registry. The orchestration
is complete only when `herdr agent list` shows none of this orch's workers still
running: every worker retired, or its open tab justified in the registry.

## Stop conditions

Stop and report instead of improvising when:

- Herdr rejects a valid workspace, tab, or pane ref, or `herdr status` shows no
  running server.
- a worker TUI rejects the model alias, auth state, working directory, or a
  startup flag — report the exact blocker, and get user approval before
  downgrading a model or switching tools.
- authentication blocks the TUI.
- a worker's status stays `unknown` while output scrolls and `agent explain`
  shows no matched rule — detection is broken or the pane is running a headless
  process.
- a plan-mode status line or acceptance menu cannot be confirmed via `agent
  read` or `pane wait-output`, or a worker's plan stays out of scope after a
  re-planning round.
- workers need overlapping edits the orch cannot integrate safely.
- a task needs focus-changing Herdr verbs the user has not approved.
