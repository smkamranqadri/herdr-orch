---
name: herdr-orch
description: "Coordinates Claude Code, Codex and Command Code worker agents from one orch session over the Herdr CLI, one named tab per worker: launch, prompt, track turns, verify and retire. Use when the user asks to delegate work to Herdr workers or run several agents through Herdr."
disable-model-invocation: true
metadata:
  author: smkamranqadri
  version: "0.4.0"
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
- **agent name** — `<orch-id>-<slice>`, e.g. `perms-fix-loops`. The whole
  name must match `[a-z][a-z0-9_-]{0,31}` and be unique among live agents.
  Every `agent …` verb accepts it in place of a pane id.

## Workers are TUIs — no headless runners

A worker is an interactive TUI — `claude`, `codex` or `cmd` (Command Code). The
first two start with `herdr agent start`, which validates the agent's identity and returns only once Herdr sees it
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
- Act only on the tabs, panes, agents and worktrees in your registry, plus agents
  the owner names (record them first). Other orchs may share the workspace;
  anything else is read-only to you.
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
herdr integration status     # selected runtime must show `current` (cmd has none)
herdr pane current --current # caller pane / tab / workspace ids
herdr agent list             # agents already running
```

Check/install only the integration for each selected runtime. Reuse this
preflight in the same workspace while the daemon and integrations are unchanged;
a new packet alone does not require repeating it.

Pick an orch id: the task slug, for example `perms`. It must be unused: no live
agent in `herdr agent list` starts with `<orch-id>-`, `git branch --list
'<orch-id>-*'` is empty, and `${TMPDIR:-/tmp}/herdr-orch/<orch-id>/` does not
exist. Record it in the registry; it prefixes every agent name, worktree
branch and brief folder.

A Codex orch needs access to the Herdr socket: its default sandbox fails every
`herdr` command with `PermissionDenied`. If `herdr status` fails that way, stop
and ask the owner to restart the orch with `--sandbox danger-full-access`.

## Delegation packets

Write each packet to a file,
`${TMPDIR:-/tmp}/herdr-orch/<orch-id>/<agent-name>.md`, and send the worker only a
pointer: `The user asked for this: read <packet path> in full and follow it.`
For a follow-up, update the packet file and point at the changed part. Each
packet is a standalone contract. Include:

- repo path and exact objective
- worker role and model
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
perms-fix-loops | claude | opus | high | "opus: fix loops" | yes | touches retry core
perms-audit-auth | codex | <model> | medium | "codex: audit auth" | no | read-only review
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
  --branch <agent-name> --label "<agent-name>" --no-focus
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
herdr agent start perms-fix-loops --kind claude --pane <root_pane_id> -- \
  --model opus --effort high --dangerously-skip-permissions "<pointer>"

herdr agent start perms-audit-auth --kind codex --pane <root_pane_id> -- \
  -m <model> -c model_reasoning_effort=medium --yolo
```

Capture `tab_id`, `pane_id`, and the agent name in the registry — retiring and
screen reads need all three.

Claude always launches with `--dangerously-skip-permissions` and Codex with
`--yolo` — workers run unattended and must not stall on permission prompts.
Never change a worker's permission flags (for example to
`--permission-mode acceptEdits`) unless the owner names that choice.

If the host blocks a launch (for example Claude Code's auto-mode check), do not
retry it and do not try other flags or tools to get the same launch through.
Tell the owner it was blocked and offer the two choices that are theirs: run the
exact command themselves (in Claude Code, `! <command>`), or re-run the
herdr-orch installer with `--claude-automode yes` and start a new Claude session.
Then wait.

`agent start` returns success only after Herdr detects the agent ready, so a
non-zero exit is the launch failure — read the tab's root pane (`herdr pane read
<pane_id> --source visible`) before retrying. Confirm the label stuck with
`herdr tab list --workspace "$HERDR_WORKSPACE_ID"`; if the tab shows a default
label, restore it:

```bash
herdr tab rename <tab_id> "opus: fix loops"
```

On `agent_not_ready`, read the pane. Claude asks before it works in a folder it
has not seen: "Accessing workspace: <folder>" and "Quick safety check: Is this a
project you created or one you trust?", with `❯ No, exit` selected and
`Yes, I trust this folder` below it. Enter alone picks "No, exit" and Claude
quits. If the folder it names is the worker's recorded launch folder (the tab's
`--cwd` from the approved proposal), send `herdr agent send-keys <name> down`,
read the pane again until `❯` marks "Yes, I trust this folder", then send
`herdr agent send-keys <name> enter` and confirm with `herdr agent get <name>`
that the worker is working. Codex launched with its approval and sandbox flags
showed no trust prompt. Any other dialog, or a trust prompt for any other
folder, goes to the owner.

If the agent name did not stick (a startup timeout), address the worker by its
pane id; every `agent` verb and `wait-turn.sh` accept it.

### Command Code workers

Herdr has no `agent start` kind for Command Code, so start it bare and name it:

```bash
herdr pane run <root_pane_id> "cmd -t --yolo -m <model> --effort <effort>"
herdr agent get <root_pane_id>   # ready once it shows agent "cmd"
herdr agent rename <root_pane_id> perms-docs
```

`--effort` values depend on the model (`deepseek/deepseek-v4-flash` takes only
off, high or max, and a wrong one exits at once); leave it out for the model's
default. `-t` trusts the folder, so there is no trust prompt. Arm `wait-turn.sh`
(baseline `0`), then send every turn, the first included, as literal text and
Enter; `agent prompt` does not reach it:

```bash
herdr pane send-text <pane_id> "The user asked for this: read <packet path> in full and follow it."
herdr pane send-keys <pane_id> enter
```

With `--yolo` it can reach outside its folder; pick claude or codex for slices
that need tight confinement. It writes `.commandcode/` into its folder: that is
its own state, never committed and not counted against the claim.

## Sending prompts to running TUIs

For claude and codex, prefer passing the packet pointer (see Delegation packets)
as launch argv — the session starts working immediately and skips the TUI-ready
race. Command Code takes every turn by `pane send-text` (see Command Code
workers).

For a claude or codex follow-up, use `agent prompt` — it submits text plus Enter atomically,
honoring the pane's live bracketed-paste mode, and `--wait` blocks until the
worker settles:

```bash
herdr agent prompt perms-fix-loops \
  "The user asked for this: read <packet path> §Follow-up 2 and follow it." \
  --wait --timeout 300000
```

A trailing `\n` in `pane send-text` does not submit — a TUI renders it as a soft
newline and the prompt sits unsubmitted. An unconfirmed send is not delivered:
if `--wait` returns `agent_prompt_stalled`, the worker never changed state —
read the screen and resend.

## Track workers

Worker slices take minutes to hours. Track each turn with the shipped watcher,
never a hand-written wait loop: every orch that wrote its own missed finished
workers or woke itself every few minutes for nothing.

Orch reads never mark a tab seen, so an unfocused worker settles as `done`, but
a tab the user has viewed settles as `idle`; both mean stopped. Neither tracks
turns: a worker still `done` from its last turn matches a wait at once. Before
each prompt, record the worker's `completion_seq` from `herdr agent get <name>`
as the turn's baseline (Herdr omits the field while a worker is working, and on
some agents altogether). With no recorded value, pass `auto`, never `0`: a
stopped worker that has run turns reads as finished at once against `0`. Use
`0` only for a worker this orch launched in this run.

Then start the watcher once for the turn, as a background job (Claude Code:
`run_in_background`, no tool timeout needed). `<skill dir>` is the folder
holding this SKILL.md (installed: `~/.agents/skills/herdr-orch`):

```bash
<skill dir>/scripts/wait-turn.sh perms-fix-loops <baseline> [stall-s 600] [backstop-s 3600] [srv]
```

It blocks on Herdr's own waits and prints one line only when something
happens, so a Claude Code orch spends nothing while the worker runs: a
20-minute turn cost it no API calls (2026-10-24). A Codex orch cannot wait that
way: its shell tool returns while the script runs, so it has to keep polling the
same run, about 2–3 API calls a minute in the same test. In Codex, start the
script once and poll that run with the longest yield the tool allows; never
start a second run. For long slices, prefer a Claude Code orch. Do not check in,
read the screen, or post progress turns while it runs. Act on its line:

| Line | Do |
| --- | --- |
| `finished seq=N status=S srv=M waited=Ns` | Verify the worker's report (see Verify worker output). |
| `blocked seq=N srv=M` | Read the screen; answer from the packet or ask the owner. |
| `stalled seq=N status=working srv=M quiet=Ns` | No screen change for stall-s while working: read the screen; a silent long step is possible, so re-arm if it is healthy. |
| `backstop seq=N status=S srv=M` | Read the screen once and re-arm with the same baseline. |
| `restarted seq=N status=S srv=M` | The Herdr server restarted and counters reset: read the screen, then re-run with the current seq as baseline and the new `srv`. |
| `gone srv=M` | The worker exited or was replaced: read the pane and tell the owner. |
| `error <message>` | Herdr could not be read: check `herdr status`, then tell the owner. |

Pass each printed `srv` back as the last argument of the next run. Size the
backstop to the slice: an hour suits most, longer for builds that run for
hours. When a reported status looks wrong, debug detection with
`herdr agent explain <pane_id> --json`. `herdr pane wait-output <pane_id>
--match "<text>"` waits for specific output, such as a dialog.

Two traps when reading panes and stopping jobs:

- The text after `❯` in a Claude pane can be Claude Code's prompt suggestion,
  not typed input; typing replaces it.
- Stop a background job by its task id or PID. `pkill -f '<pattern>'` also
  matches the orch's own command line when that holds the pattern, and kills
  it.

Maintain a compact registry in the existing task notes or handoff: orch
identity; worker agent name, tab label, role, model; workspace/tab/pane ids;
objective sent and start time; status (starting, running, blocked, reported,
verified, retired); claimed files or work slice; worker-reported commands and
results; orch verification performed; final disposition (accepted, rejected,
superseded, or blocked).

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
- Before integrating, check that `git status` in the main checkout is clean,
  with no merge, rebase or cherry-pick in progress; another orch may be
  mid-merge. If not, stop and tell the owner.
- Have the worker commit its work, then trial-merge its branch tip against
  current main: `git merge-tree --write-tree main <branch>`. A conflict, for
  example with another orch's merged work, goes to the owner.
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
- workers need overlapping edits the orch cannot integrate safely.
- a task needs focus-changing Herdr verbs the user has not approved.
