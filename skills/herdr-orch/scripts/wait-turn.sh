#!/usr/bin/env bash
# Wait for one Herdr worker's turn to end, without waking the orch in between. Run it once per
# turn as a background job. It loops on Herdr's own waits and prints exactly one line when
# something happens:
#   finished seq=N status=S srv=M waited=Ns   the turn ended (idle or done)
#   blocked seq=N srv=M                       the worker waits on a question or menu
#   stalled seq=N status=working srv=M quiet=Ns   "working", but the screen has not changed
#   gone srv=M                                the agent is no longer there
#   restarted seq=N status=S srv=M            the Herdr server restarted (new marker or seq)
#   backstop seq=N status=S srv=M             backstop-seconds passed with none of the above
#   error <message>                           Herdr could not be read (exit 1)
# seq is "-" when Herdr does not report completion_seq. Pass the printed srv back as
# server-marker on the next run.
set -uo pipefail

usage="usage: wait-turn.sh <name> <baseline|auto> [stall-seconds] [backstop-seconds] [server-marker]"
die() { echo "error $*"; exit 1; }

name="${1:-}"; base="${2:-}"; stall="${3:-600}"; backstop="${4:-3600}"; expect="${5:-}"
[[ -n "$name" && "$base" =~ ^([0-9]+|auto)$ ]] || die "$usage"
[[ "$stall" =~ ^[0-9]+$ && "$backstop" =~ ^[0-9]+$ ]] || die "$usage"
[[ -z "$expect" || "$expect" =~ ^[0-9]+$ ]] || die "$usage"

# The server marker: the inode of the socket `herdr status` names under "server:". A restarted
# server makes a new socket, so the inode changes.
marker() {
  local out
  out="$(herdr status 2>&1)" || return 1
  printf '%s\n' "$out" | python3 -I -c '
import os, sys
section = None
for line in sys.stdin:
    text = line.rstrip("\n")
    if text and not text[0].isspace():
        section = text.strip()
    elif section == "server:" and text.strip().startswith("socket:"):
        try:
            print(os.stat(text.split(":", 1)[1].strip()).st_ino)
        except OSError:
            sys.exit(1)
        sys.exit(0)
sys.exit(1)'
}

# One agent read: "ok <seq|-> <status> <revision>", "gone", or "bad <message>".
read_agent() {
  herdr agent get "$name" 2>&1 | python3 -I -c '
import json, sys
try:
    data = json.loads(sys.stdin.read())
except ValueError:
    print("bad unparseable output from herdr agent get"); sys.exit()
error = data.get("error") if isinstance(data, dict) else None
if isinstance(error, dict):
    code = error.get("code")
    print("gone" if code == "agent_not_found" else "bad herdr agent get failed: %s" % code)
    sys.exit()
result = data.get("result") if isinstance(data, dict) else None
agent = result.get("agent") if isinstance(result, dict) else None
if not isinstance(agent, dict) or agent.get("agent_status") not in ("idle", "working", "blocked", "done", "unknown"):
    print("bad herdr agent get output has no result.agent"); sys.exit()
seq = agent.get("completion_seq")
print("ok", seq if type(seq) is int else "-", agent["agent_status"], agent.get("revision", 0))'
}

# One wait slice. Returns 0 when the wait ended or hit its own timeout, 1 on any other failure.
wait_slice() {
  local seconds="$1" out
  shift
  out="$(herdr agent wait "$name" "$@" --timeout "$((seconds * 1000))" 2>&1)" && return 0
  printf '%s' "$out" | python3 -I -c '
import json, sys
try:
    code = json.loads(sys.stdin.read())["error"]["code"]
except Exception:
    sys.exit(1)
sys.exit(0 if code == "timeout" else 1)'
}

if [[ -z "$expect" ]]; then
  expect="$(marker)" || die "cannot read the Herdr server marker"
fi
known=""                     # the baseline, once known
[[ "$base" == auto ]] || known="$base"
start="$(date +%s)"; first=1; seen_working=0; stall_from=""; last_rev=""; wait_failed=0

while :; do
  m1="$(marker)" || die "cannot read the Herdr server marker"
  read -r kind seq status rev <<<"$(read_agent)"
  m2="$(marker)" || die "cannot read the Herdr server marker"
  now="$(date +%s)"

  # 1. restart: a new server marker, or the counter went below the baseline
  if [[ "$m1" != "$expect" || "$m2" != "$expect" ]]; then
    new="$m2"; [[ "$m2" == "$expect" ]] && new="$m1"
    [[ "$kind" == ok ]] || { seq="-"; status="-"; }
    echo "restarted seq=$seq status=$status srv=$new"; exit 0
  fi
  # 2. gone
  [[ "$kind" == gone ]] && { echo "gone srv=$expect"; exit 0; }
  [[ "$kind" == ok ]] || die "${seq:-} ${status:-} ${rev:-}"
  if [[ "$first" == 1 && "$base" == auto && "$status" != working && "$seq" != - ]]; then
    known="$seq"
  fi
  first=0
  if [[ -n "$known" && "$seq" != - ]] && (( seq < known )); then
    echo "restarted seq=$seq status=$status srv=$expect"; exit 0
  fi
  # A wait that failed for a reason other than its timeout is an error unless rules 1-2 explain it.
  [[ "$wait_failed" == 1 ]] && die "herdr agent wait failed for $name"

  if [[ "$status" == working ]]; then
    seen_working=1
    [[ -z "$stall_from" || "$rev" != "$last_rev" ]] && stall_from="$now"
  else
    stall_from=""
  fi
  last_rev="$rev"

  # 3. blocked
  [[ "$status" == blocked ]] && { echo "blocked seq=$seq srv=$expect"; exit 0; }
  # 4. finished
  if [[ "$status" == idle || "$status" == done ]]; then
    if [[ "$seen_working" == 1 ]] || { [[ -n "$known" && "$seq" != - ]] && (( seq > known )); }; then
      echo "finished seq=$seq status=$status srv=$expect waited=$((now - start))s"; exit 0
    fi
  fi
  # 5. stalled
  if (( stall > 0 )) && [[ "$status" == working ]] && (( now - stall_from >= stall )); then
    echo "stalled seq=$seq status=working srv=$expect quiet=$((now - stall_from))s"; exit 0
  fi
  # 6. backstop
  left=$((backstop - (now - start)))
  (( left > 0 )) || { echo "backstop seq=$seq status=$status srv=$expect"; exit 0; }

  # 7-8. wait for the next change, in short slices so the checks above keep running
  wait_failed=0
  if [[ "$status" == working ]]; then
    wait_slice "$(( left < 60 ? left : 60 ))" || wait_failed=1
  else
    wait_slice "$(( left < 30 ? left : 30 ))" --until working --until blocked || wait_failed=1
  fi
done
