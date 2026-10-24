# Plan: PERMS column and launch gates

Date: 2026-10-24. Owner: the user. Mode: Standard. Scope approved 2026-10-24.

## Problem

An orch in Claude Code auto mode cannot always launch a worker: the auto-mode classifier blocks
by default "launching an autonomous agent loop that runs without human approval or a sandbox,
such as one started with `--dangerously-skip-permissions`". On 2026-10-24 it blocked two
`--dangerously-skip-permissions` launches and a Codex `--yolo` launch, each after a bare "go".
Per the Claude Code permission-modes docs (read 2026-10-24), an approval in conversation clears a
block only when it names the action and what makes it dangerous. The worker proposal names
neither. The same day, a launch whose proposal line named its permission flags
(`--sandbox danger-full-access -a never`, "no sandbox, no approvals") passed after a bare "go".

Three launch gates also showed up that the skill does not cover:

- another orch read a bare "go" after a three-option menu as permission to launch with
  `--permission-mode acceptEdits`, and the worker then stalled on approvals;
- a folder the TUI has not seen makes it ask first, so `agent start` returns `agent_not_ready`;
  Claude asks "Is this a project you created or one you trust?" and Codex asks "Trust this
  folder?" with "1. Trust and continue";
- a startup timeout left a worker without its agent name, so only its pane id addressed it.

## Decisions (owner, 2026-10-24)

- A bare "go" after a proposal line with a PERMS column approves the launch; the owner does not
  have to repeat the flags.
- The orch answers the folder-trust prompt itself, for the folder it launched the worker in, and
  does not hand it to the owner. That folder is the worker's recorded launch folder: the tab's
  `--cwd` from the approved proposal (the repo, a worktree the orch created, or another folder
  the proposal named).
- The launch flags stay as decided in [project.md](../knowledge/project.md).
- Prove it live with two throwaway workers, one Claude and one Codex.

## Tasks

- [x] 1. `SKILL.md` "Propose workers": add a `PERMS` column to the template line and both
  examples, naming the permission flags and what they turn off (`--dangerously-skip-permissions
  (no approvals)`, `--yolo (no approvals, no sandbox)`). One go covers each line shown; a
  changed PERMS needs a new go.
  Status: reverted 2026-10-25 by the owner (a12f7bf): the classifier ignores the column.
- [x] 2. `SKILL.md` "Launch workers":
  - If the host blocks a launch (for example Claude Code's auto-mode check), do not retry it
    and do not try other flags or tools to get the same launch through. Tell the owner it was
    blocked and offer the two choices that are theirs: run the exact command themselves (in
    Claude Code, `! <command>`), or add the allow rule `Bash(herdr agent start:*)`, which
    pre-approves every launch with any flags. Then wait.
  - Never change a worker's permission flags (for example to `--permission-mode acceptEdits`)
    unless the owner names that choice.
  - On `agent_not_ready`, read the pane. If it is the TUI's folder-trust prompt and the folder
    the prompt names is the worker's recorded launch folder (the tab's `--cwd` from the approved
    proposal), answer the default option with `herdr agent send-keys <name> enter`, then confirm with
    `herdr agent get` that the worker is working. Any other dialog, or a trust prompt for any
    other folder, goes to the owner.
  - If the agent name did not stick (a startup timeout), address the worker by its pane id;
    every `agent` verb and `wait-turn.sh` accept it.
- [x] 3. `evals/evals.json` eval 1 (`spawn-gate`): the proposal-line behaviour lists PERMS.
  Status: reverted 2026-10-25 by the owner (a12f7bf): the classifier ignores the column.
- [x] 4. `CHANGELOG.md` 0.3.0 section; `metadata.version` 0.2.1 to 0.3.0.
- [x] 5. Live run, both kinds: propose two throwaway workers with PERMS lines, each in a new
  empty folder under this session's scratchpad, task "reply ok": `claude` `haiku` low with
  `--dangerously-skip-permissions`, and `codex` `gpt-6.1-sol` low with `--yolo`. The owner
  answers a bare "go". Record for each: whether auto mode passed the launch, the trust prompt's
  exact text and the key that answered it, and the worker's reply. Retire both. If the
  classifier blocks a launch, follow task 2's blocked-launch rule and record that instead.
  Status: done 2026-10-24. On the bare "go" the Claude launch was blocked (`[Create Unsafe Agents]`) and not retried; after the owner added an `autoMode.allow` rule both launches passed and replied ok. No trust prompt appeared for either.
- [x] 6. For each kind whose launch reached its trust prompt in task 5, make the prompt text and
  key in `SKILL.md` match what task 5 recorded. A kind whose launch was blocked stays marked
  unverified in `SKILL.md`; no text is invented and the launch is not retried.
  Status: done 2026-10-24. Neither kind reached a trust prompt, so both texts stay marked unverified.

## Out of scope

Changing launch flags, installing an allow rule, plan-mode launch details beyond the template,
the other Next items, pushing or releasing.

## Acceptance

- `tests/run.sh` passes; `test-skill.sh` confirms every Herdr command the new text names.
- `SKILL.md` stays under 500 lines.
- Task 5: both launches pass auto mode on a bare "go" with no block, the orch answers both trust
  prompts, and both workers reply ok; or, if one is blocked, the orch follows the blocked-launch
  rule and the plan records the block.
- For each kind that reached its trust prompt, the text and key in `SKILL.md` are the ones task 5
  recorded; a blocked kind is marked unverified.

## Risks and assumptions

- The classifier is not deterministic; one bare "go" passing a PERMS launch is a single data
  point.
- Answering a trust prompt trusts the folder's settings, which can run code. The rule limits it
  to folders the orch launched in.
- Claude's trust-prompt wording comes from one screen read on 2026-10-24; task 5 re-checks it.

## Review
- Reviewed: 2026-10-24 by codex gpt-6.1-sol (medium); plan hash 49396259e4f2
- [fixed] Trust handling allowed only the repo or an orch-created worktree, so the live test's scratch folders would hand both prompts to the owner - the rule now covers the worker's recorded launch folder (the tab's --cwd from the approved proposal), and the prompt's named folder must match it
- [fixed] Task 6 required trust-prompt evidence a blocked launch never produces - task 6 and acceptance apply only to kinds that reached the prompt; a blocked kind stays marked unverified, with no invented text and no retry
