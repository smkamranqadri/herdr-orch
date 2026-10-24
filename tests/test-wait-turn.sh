#!/usr/bin/env bash
# wait-turn.sh against a fake herdr and a fake clock on PATH. Each case scripts what Herdr
# answers to `status`, `agent get` and `agent wait`, then checks the one line the script prints,
# its exit code, and the exact waits it made.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
script="$repo_root/skills/herdr-orch/scripts/wait-turn.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

test -x "$script" || fail "wait-turn.sh missing or not executable"

# Two socket files stand in for two server instances; their inodes are the markers.
sock_a="$tmp/a.sock"; sock_b="$tmp/b.sock"; : >"$sock_a"; : >"$sock_b"
A="$(python3 -I -c 'import os,sys; print(os.stat(sys.argv[1]).st_ino)' "$sock_a")"
B="$(python3 -I -c 'import os,sys; print(os.stat(sys.argv[1]).st_ino)' "$sock_b")"

mkdir -p "$tmp/bin"
cat >"$tmp/bin/date" <<'EOF'
#!/bin/sh
cat "$FAKE/clock"
EOF
cat >"$tmp/bin/herdr" <<'EOF'
#!/usr/bin/env python3
# Fake herdr: answers from $FAKE/scenario.json, one queue per command (the last entry repeats;
# an empty wait queue times out). Logs every call to $FAKE/calls.
import json, os, sys
fake = os.environ["FAKE"]
args = sys.argv[1:]
with open(os.path.join(fake, "calls"), "a") as log:
    log.write(" ".join(args) + "\n")
if sum(1 for _ in open(os.path.join(fake, "calls"))) > 400:
    sys.exit("fake herdr: call limit reached")   # a looping script ends instead of hanging
scen = json.load(open(os.path.join(fake, "scenario.json")))
state_path = os.path.join(fake, "state.json")
state = json.load(open(state_path)) if os.path.exists(state_path) else {}

def take(queue):
    items = scen.get(queue, [])
    i = state.get(queue, 0)
    state[queue] = i + 1
    json.dump(state, open(state_path, "w"))
    if not items:
        return None
    return items[min(i, len(items) - 1)]

def advance(seconds):
    clock = os.path.join(fake, "clock")
    now = int(open(clock).read())
    open(clock, "w").write(str(now + seconds))

def error(cmd, code, message="x"):
    sys.stderr.write(json.dumps({"error": {"code": code, "message": message}, "id": cmd}) + "\n")
    sys.exit(1)

if args[:1] == ["status"]:
    sock = take("status")
    print("client:\n  version: 0.9.5\n  channel: stable\n\nserver:\n  status: running\n"
          "  version: 0.9.5\n  socket: %s\n\nupdate:\n  restart_needed: no" % sock)
elif args[:2] == ["agent", "get"]:
    e = take("get")
    if "raw" in e:
        print(e["raw"]); sys.exit(0)
    if "err" in e:
        error("cli:agent:get", e["err"])
    agent = {"name": args[2], "agent_status": e["st"], "revision": e.get("rev", 0)}
    if e.get("seq") is not None:
        agent["completion_seq"] = e["seq"]
    print(json.dumps({"id": "cli:agent:get", "result": {"agent": agent, "type": "agent"}}))
elif args[:2] == ["agent", "wait"]:
    e = take("wait") or {"to": True}
    if "err" in e:
        error("cli:agent:wait", e["err"])
    if "ok" in e:
        advance(e["ok"]); print("{}"); sys.exit(0)
    advance(int(args[args.index("--timeout") + 1]) // 1000)
    error("cli:agent:wait", "timeout", "timed out waiting for agent status")
else:
    sys.exit("fake herdr: unexpected call: " + " ".join(args))
EOF
chmod +x "$tmp/bin/date" "$tmp/bin/herdr"

n=0
# run <scenario-json> <expected-line> <expected-exit> [wait-timeouts-ms...] -- <script args...>
# The scenario's "status" list may use "A" and "B" for the two sockets.
run() {
  local scenario="$1" want="$2" want_rc="$3" got rc waits
  shift 3
  local want_waits=()
  while [[ "$1" != -- ]]; do want_waits+=("$1"); shift; done
  shift
  n=$((n + 1))
  export FAKE="$tmp/case$n"; mkdir -p "$FAKE"; echo 1000 >"$FAKE/clock"; : >"$FAKE/calls"
  printf '%s' "$scenario" | sed "s|\"A\"|\"$sock_a\"|g; s|\"B\"|\"$sock_b\"|g" >"$FAKE/scenario.json"
  set +e
  got="$(PATH="$tmp/bin:$PATH" "$script" "$@" 2>&1)"; rc=$?
  set -e
  [[ "$got" == "$want" ]] || fail "case $n ($*): printed '$got', want '$want'"
  [[ "$rc" == "$want_rc" ]] || fail "case $n ($*): exit $rc, want $want_rc"
  waits="$(grep '^agent wait' "$FAKE/calls" | sed 's/.*--timeout //' | tr '\n' ' ' || true)"
  [[ "$waits" == "${want_waits[*]+${want_waits[*]} }" ]] \
    || fail "case $n ($*): waited with timeouts '$waits', want '${want_waits[*]:-} '"
  if grep -q -- '--until done' "$FAKE/calls"; then fail "case $n: a wait used --until done"; fi
}

W='{"st":"working","rev":1}'

# finished
run '{"status":["A"],"get":['"$W"',{"st":"idle","seq":6}],"wait":[{"ok":10}]}' \
  "finished seq=6 status=idle srv=$A waited=10s" 0 60000 -- w1 5
run '{"status":["A"],"get":[{"st":"done","seq":6}]}' \
  "finished seq=6 status=done srv=$A waited=0s" 0 -- w1 5
run '{"status":["A"],"get":['"$W"',{"st":"idle"}],"wait":[{"ok":10}]}' \
  "finished seq=- status=idle srv=$A waited=10s" 0 60000 -- w1 5
# seq missing and never seen working: not finished; stopped waits are 30 s slices for working|blocked
run '{"status":["A"],"get":[{"st":"idle"}]}' \
  "backstop seq=- status=idle srv=$A" 0 30000 30000 -- w1 5 600 60
grep -c -- '^agent wait w1 --until working --until blocked --timeout 30000$' "$FAKE/calls" | grep -qx 2 \
  || fail "stopped waits must be --until working --until blocked in 30 s slices"
# blocked, gone
run '{"status":["A"],"get":[{"st":"blocked","seq":6}]}' "blocked seq=6 srv=$A" 0 -- w1 5
run '{"status":["A"],"get":[{"err":"agent_not_found"}]}' "gone srv=$A" 0 -- w1 5
# restarted by marker, with seq below, equal to and above the baseline
for s in 3 5 9; do
  run '{"status":["B"],"get":[{"st":"idle","seq":'"$s"'}]}' \
    "restarted seq=$s status=idle srv=$B" 0 -- w1 5 600 3600 "$A"
done
# restarted by seq rollback
run '{"status":["A"],"get":[{"st":"idle","seq":2}]}' "restarted seq=2 status=idle srv=$A" 0 -- w1 5
# restarted between the marker read and agent get: not finished, not gone
run '{"status":["A","B"],"get":[{"st":"idle","seq":9}]}' \
  "restarted seq=9 status=idle srv=$B" 0 -- w1 5 600 3600 "$A"
run '{"status":["A","B"],"get":[{"err":"agent_not_found"}]}' \
  "restarted seq=- status=- srv=$B" 0 -- w1 5 600 3600 "$A"
# stalled: revision frozen while working
run '{"status":["A"],"get":['"$W"']}' \
  "stalled seq=- status=working srv=$A quiet=120s" 0 60000 60000 -- w1 0 100 3600
# not stalled while revision moves
run '{"status":["A"],"get":[{"st":"working","rev":1},{"st":"working","rev":2},{"st":"working","rev":3},{"st":"idle","seq":1}]}' \
  "finished seq=1 status=idle srv=$A waited=180s" 0 60000 60000 60000 -- w1 0 100 3600
# a long stopped period, then a short quiet working one: not stalled
run '{"status":["A"],"get":[{"st":"idle","seq":5,"rev":1},{"st":"idle","seq":5,"rev":1},{"st":"idle","seq":5,"rev":1},{"st":"idle","seq":5,"rev":1},'"$W"','"$W"',{"st":"idle","seq":6}]}' \
  "finished seq=6 status=idle srv=$A waited=240s" 0 30000 30000 30000 30000 60000 60000 -- w1 5 100 3600
# working, then unknown for a while, then working again: the stall clock restarts
run '{"status":["A"],"get":['"$W"',{"st":"unknown","rev":1},{"st":"unknown","rev":1},{"st":"unknown","rev":1},'"$W"',{"st":"idle","seq":6}]}' \
  "finished seq=6 status=idle srv=$A waited=210s" 0 60000 30000 30000 30000 60000 -- w1 5 100 3600
# stall-seconds 0 never stalls; backstop with the last slice cut to the time left
run '{"status":["A"],"get":['"$W"']}' \
  "backstop seq=- status=working srv=$A" 0 60000 30000 -- w1 0 0 90
# auto: working at start, then settles
run '{"status":["A"],"get":['"$W"',{"st":"idle","seq":3}],"wait":[{"ok":5}]}' \
  "finished seq=3 status=idle srv=$A waited=5s" 0 60000 -- w1 auto
# auto: stopped with a seq at start becomes the baseline
run '{"status":["A"],"get":[{"st":"idle","seq":4},{"st":"idle","seq":4},{"st":"done","seq":5}]}' \
  "finished seq=5 status=done srv=$A waited=60s" 0 30000 30000 -- w1 auto
# auto: stopped with no seq, then idle(12) without working: never finished
run '{"status":["A"],"get":[{"st":"idle"},{"st":"idle","seq":12}]}' \
  "backstop seq=12 status=idle srv=$A" 0 30000 30000 -- w1 auto 600 60
# a whole turn lands between the read and the wait: caught on the next slice
run '{"status":["A"],"get":[{"st":"idle","seq":5},{"st":"done","seq":6}]}' \
  "finished seq=6 status=done srv=$A waited=30s" 0 30000 -- w1 5
# wait failures: removed is gone, restarted is restarted, anything else is an error
run '{"status":["A"],"get":['"$W"',{"err":"agent_not_found"}],"wait":[{"err":"agent_not_found"}]}' \
  "gone srv=$A" 0 60000 -- w1 5
run '{"status":["A","A","A","B"],"get":['"$W"'],"wait":[{"err":"server_not_running"}]}' \
  "restarted seq=- status=working srv=$B" 0 60000 -- w1 5
run '{"status":["A"],"get":['"$W"'],"wait":[{"err":"internal"}]}' \
  "error herdr agent wait failed for w1" 1 60000 -- w1 5
# Herdr down and bad output are errors
run '{"status":["A"],"get":[{"err":"server_not_running"}]}' \
  "error herdr agent get failed: server_not_running" 1 -- w1 5
run '{"status":["A"],"get":[{"raw":"not json"}]}' "error unparseable output from herdr agent get" 1 -- w1 5
run '{"status":["A"],"get":[{"raw":"{\"id\":\"cli:agent:get\",\"result\":{}}"}]}' \
  "error herdr agent get output has no result.agent" 1 -- w1 5
# bad arguments
usage="error usage: wait-turn.sh <name> <baseline|auto> [stall-seconds] [backstop-seconds] [server-marker]"
run '{"status":["A"],"get":['"$W"']}' "$usage" 1 -- w1 nope
run '{"status":["A"],"get":['"$W"']}' "$usage" 1 -- w1

echo "ok ($n cases)"
