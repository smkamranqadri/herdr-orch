# Plan: watcher fix (wait-turn.sh)

Date: 2026-10-24. Owner: the user. Mode: Standard. Scope approved 2026-10-24; revised the same
day to event mode (owner-approved), so the plan needs a new review.

## Problem

The "Track workers" recipe (`SKILL.md:233-254` in 0.1.0) and `references/plan-mode.md:175-176`
wait with `--until done`. A worker that settles as `idle` is only noticed at the check-in
timeout. On 2026-10-24 four orchs wrote their own wait loops and each had a bug: one
orch missed two finished workers (`--until blocked`, then `--until done`), and another
orch polled status every 20 s with no `completion_seq` baseline. Herdr behaviour:
[herdr.md](../knowledge/herdr.md).

Cost: a watcher that exits at every check-in wakes the orch each time. One orch
(~580k context) spent about 3 API calls and 1.7M cache-read tokens per 5-minute check-in. The
third orch kept its 5-minute waits inside one background job that exits only when the turn
settles, and woke once per turn (a Codex worker, seq 60 at 20:03:12 and seq 64 at 20:15:59).

## Decisions (owner, 2026-10-24)

- Ship the loop as a script in the skill, not inline text.
- On a Herdr server restart the script reports `restarted` and stops; the orch reads the screen
  and re-runs it with the new baseline.
- Detect a restart by a server marker, with the seq rollback kept as a backup.
- Event mode: one run loops internally and exits only on an event, a stall or the backstop. It
  never exits just because a check-in interval passed. (Replaces "one check-in per run".)
- Add eval scenario 4 `idle-finish`; `stale-done` stays unchanged.
- Verify a Codex orch in this plan, not only Claude Code (after review round 2, finding 6).

## Script contract

`skills/herdr-orch/scripts/wait-turn.sh <name> <baseline|auto> [stall-seconds, default 600]
[backstop-seconds, default 3600] [server-marker]`

The server marker is the inode of the socket that `herdr status` names under `server:`. A
restart makes a new socket: the side-projects server restarted at 19:07:36 on 2026-10-24, and
its socket carries that time and a new inode. Without the argument the script reads the marker
at start; the orch passes back the one the previous line printed.

Baseline `auto`: if the worker is working at start, its next settle counts; if it is stopped
with a seq, that seq is the baseline; if it is stopped with no seq, the baseline stays unknown
and only rule 4's seen-working branch can report `finished`. A numeric baseline is the seq the
orch recorded before its prompt; 0 for a fresh worker.

Each pass reads the marker, then `herdr agent get <name>` (status, `revision`, and
`completion_seq` only when Herdr reports it), then the marker again; the pass uses the agent
read only if both marker reads match the expected marker, and otherwise reports `restarted`. A
missing seq is unknown, never 0: it is absent while working, on a fresh worker, and on some idle
agents (2026-10-24). The script notes whether it has seen the worker `working`
during this run. The stall clock starts when the worker is first seen `working` after being
seen in any other state (or at start if it is working then), and restarts on every `revision`
change. The first rule that matches wins:

1. a marker read different from the expected marker, or seq present and below a known baseline:
   `restarted seq=N status=S srv=M`
2. `agent get` says the agent is not found: `gone srv=M`
3. status `blocked`: `blocked seq=N srv=M`
4. status `idle` or `done`, and seq present and above a known baseline, or the worker was seen
   working this run: `finished seq=N status=S srv=M waited=Ns`
5. stall-seconds above 0, status `working`, and the stall clock at or past stall-seconds:
   `stalled seq=N status=working srv=M quiet=Ns`
6. backstop-seconds since start: `backstop seq=N status=S srv=M`
7. status `working`: `herdr agent wait <name>` (no `--until`) for at most 60 s, then the next pass
8. otherwise (stopped with seq not risen, or `unknown`): `herdr agent wait <name> --until working
   --until blocked` for at most 30 s, then the next pass

The slices keep the marker and stall checks running and catch a turn that starts and ends
between a read and a wait; they never wake the orch. Each wait's `--timeout` is the slice or the
time left to the backstop, whichever is smaller. A missing seq prints as `-`. The script prints
exactly one line and exits 0. A wait that ends with Herdr's `timeout` error (exit 1,
`"code":"timeout"`) is normal. A wait that fails with any other error starts a fresh pass at
once, so rules 1 and 2 can report `restarted` or `gone`; only if that pass establishes neither
does the script print `error`. A failed `agent get` other than not-found, a failed `herdr status`
or `stat`, or output that is not the expected JSON prints `error <message>` and exits 1. JSON is
parsed with `python3 -I`.

`stalled` is a judgement call, not proof: a healthy step that changes nothing on screen for
stall-seconds reports it too. Both TUIs tick a timer while working, which moves `revision`, so
this should be rare; stall-seconds 0 turns the check off.

## Tasks

- [ ] 1. `skills/herdr-orch/scripts/wait-turn.sh` per the contract, executable.
- [ ] 2. `tests/test-wait-turn.sh`: a fake `herdr` on PATH that serves scripted `status` and
  `agent get` answers (including `revision`), returns Herdr's real timeout JSON with exit 1 for
  an expiring wait, and logs every `agent wait` argv. Cases: finished from idle, finished from
  done, finished with seq missing after being seen working, not finished when seq is missing and
  the worker was never seen working, blocked, gone, restarted by marker (seq below, equal to and
  above baseline), restarted by seq rollback, stalled (revision frozen while working), not
  stalled while revision moves, backstop, `auto` baseline from working and from stopped, stale
  stopped worker gets `--until working --until blocked` in slices of at most 30 s, a full turn
  landing between the read and the wait is reported `finished`, a wait timeout is not an error,
  Herdr down is an error, malformed JSON and a missing `result.agent` are errors. Review round 2
  adds: `auto` on a stopped worker with no seq, then `idle(seq=12)` without a working state, is
  not `finished`; a restart between the marker read and `agent get` is `restarted`, not
  `finished` or `gone`; a wait that fails because the worker was removed is `gone`, and one that
  fails because the server restarted is `restarted`; a long stopped period followed by a short
  working one is not `stalled`; a quiet working step under stall-seconds is not `stalled`;
  stall-seconds 0 never reports `stalled`. Every case
  asserts the exact output line (`^...$`) and the exit code; wait calls assert the exact
  `--timeout` milliseconds; no logged call has `--until done`. Tests pass small stall and
  backstop values so the suite stays fast.
- [ ] 3. Mutation check: break each rule in turn with a literal edit, watch its test fail,
  restore from a saved copy and prove the file byte-identical (`cmp`). Log to
  `$TMPDIR/herdr-orch-mutations.log`.
- [ ] 4. `SKILL.md` "Track workers": record the baseline, start the script once per turn as a
  background job (Claude Code `run_in_background`; no tool timeout needed), do not check in or
  post progress turns while it runs, and act on each of its lines: `finished` verify the report;
  `blocked`, `stalled`, `gone`, `error` read the screen and tell the owner; `backstop` read the
  screen once and re-arm; `restarted` read the screen and re-run with the new baseline and
  marker. Size the backstop to the slice. For a Codex orch, write the recipe task 9b proves
  (how Codex runs a long command, its tool timeout, and whether it yields mid-call), not an
  assumed one. Add: never `pkill -f`
  with a pattern that matches the orch's own command line; the text after `❯` in a Claude pane
  can be a prompt suggestion, not typed input.
- [ ] 5. `references/plan-mode.md` "Hands-off monitoring": use the script instead of the
  done/blocked waits. The plan-review waits (`--until blocked`) stay.
- [ ] 6. `evals/evals.json` scenario 4 `idle-finish` (the owner views the helper's tab first so
  it settles as `idle`; expected: runs `wait-turn.sh` once for the turn, reports `finished` with
  a risen seq, posts no check-in turns while waiting, never waits `--until done`);
  `evals/setup.sh` accepts id 4 with scenario 2's fixture; `tests/test-evals.sh` expects ids
  `[1, 2, 3, 4]`, runs `setup.sh` for id 4 and checks its fixture.
- [ ] 7. `tests/test-install.sh`: the installed script exists and is executable.
- [ ] 8. `CHANGELOG.md` line; `metadata.version` 0.1.0 to 0.2.0.
- [ ] 9a. Live run, Claude Code orch: the script against a real worker turn of at least 10
  minutes that settles as `idle`; record the output line and the orch's API calls from start to
  that line (from its session log).
- [ ] 9b. Live run, Codex orch: a Codex orch in a Herdr tab (`--sandbox danger-full-access`, per
  [herdr.md](../knowledge/herdr.md)) runs the script against a worker turn of at least 10
  minutes; record how Codex ran it (tool, timeout, any mid-call yields) and its API calls while
  waiting (from its session log). The orch launch is proposed to the owner first.

## Out of scope

The PERMS column, Command Code, multi-orch, a Herdr plugin or daemon, brief-driven push,
running the evals, README changes beyond text that names the wait, any change to launch flags.

## Acceptance

- `tests/run.sh` passes, including `test-wait-turn.sh`.
- Each guard's mutation trips its test, and the restore is byte-identical.
- `grep -rn -- '--until done' skills/` finds nothing.
- `SKILL.md` stays under 500 lines.
- 9a prints `finished seq=N status=idle srv=M waited=Ns` with `waited` of at least 600, M the live
  socket's inode, and the Claude orch makes no API call between starting the script and that
  line.
- 9b's Codex run is recorded with its actual API calls while waiting, and `SKILL.md`'s Codex
  recipe matches what it showed. If Codex cannot wait without calls, the skill says so and gives
  the cheapest recipe 9b measured.

## Risks and assumptions

- The `agent get` and `agent wait` output shapes are Herdr 0.9.5's; re-checked live in task 9.
- `revision` rises with screen output (20 in 10 s on a working worker, 2026-10-24), but a hung
  command under a ticking spinner keeps it moving, so such a worker is caught only by the
  backstop.
- `python3` is on PATH (the tests already need it).
- Codex's shell-tool timeout and background support are unverified until task 9b.
- `stalled` can fire on a healthy step that is silent on screen for stall-seconds (see the
  contract).

## Review
- Reviewed: 2026-10-24 by codex gpt-6.1-sol (high); plan hash 08fe1cbc2949
- [fixed] A normal wait timeout (exit 1, code timeout) would print error - a wait timeout now re-reads state; only failed get/status/stat, other wait errors and bad JSON are errors, each tested
- [fixed] A turn that starts and ends between get and the --until working wait is missed until the check-in - stopped-worker waits run in slices of at most 30 s, with a test for a turn landing in that gap
- [fixed] Seq rollback misses a restart whose new counter is at or above the baseline - the owner chose a server marker (socket inode from herdr status, checked against the 19:07:36 restart); rollback stays as backup; tests cover seq below, equal to and above baseline
- [fixed] Tests matched lines but not exit codes, bad JSON or wait arguments - every case asserts its exit code; malformed JSON, missing result.agent and exact --timeout milliseconds are tested
- [fixed] test-evals did not run fixture 4 and "within one check-in" allowed the old delay - setup.sh runs for id 4 with a fixture check; the eval requires finished with a risen seq before the check-in expires
- Reviewed: 2026-10-24 by codex gpt-6.1-sol (high); plan hash 33053f17dc35
- [fixed] auto turned a missing stopped-worker seq into baseline 0 - the baseline stays unknown and only seen-working-then-settled reports finished; trace idle(-) then idle(12) tested
- [fixed] A restart between the marker read and agent get could read as finished or gone - the marker is read before and after agent get; a restart in that gap is tested
- [fixed] A non-timeout wait failure became error before the gone and restart rules - it starts a fresh pass first; error only if neither is established; both cases tested
- [fixed] The stall clock could include time spent stopped - it starts when the worker enters working and restarts on each revision change; long-stopped-then-short-working tested
- [fixed] A healthy silent step reads as stalled - documented in the contract and Risks; stall-seconds 0 turns it off; a quiet step under the budget is tested
- [fixed] The Codex foreground recipe was unverified and the live gate could pass on a short turn - the owner chose to verify Codex here: task 9b runs a Codex orch live; 9a and 9b need turns of at least 10 minutes and record API calls from session logs
