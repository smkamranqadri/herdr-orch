#!/usr/bin/env bash
# The eval scenarios parse and their sandbox builder produces each fixture.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
log="$tmp/log"

fail() { echo "FAIL: $*" >&2; cat "$log" >&2 2>/dev/null || true; exit 1; }

python3 -I - "$repo_root/evals/evals.json" <<'PY' || fail "evals.json"
import json, sys
data = json.load(open(sys.argv[1]))
assert data["skill_name"] == "herdr-orch", "skill_name"
evals = data["evals"]
assert [e["id"] for e in evals] == [1, 2, 3, 4], "ids must be 1, 2, 3, 4"
for e in evals:
    for key in ("name", "setup", "prompt"):
        assert e.get(key, "").strip(), f"eval {e['id']}: missing {key}"
    assert len(e["expected_behavior"]) >= 3, f"eval {e['id']}: needs 3+ expected behaviours"
PY

setup="$repo_root/evals/setup.sh"
skill="$repo_root/skills/herdr-orch"

bash "$setup" "$tmp/e1" 1 --with-skill "$skill" >"$log" 2>&1 || fail "setup eval 1"
test -f "$tmp/e1/src/retry.py" || fail "eval 1: src/retry.py missing"
test -f "$tmp/e1/.claude/skills/herdr-orch/SKILL.md" || fail "eval 1: Claude skill copy missing"
test -f "$tmp/e1/.agents/skills/herdr-orch/SKILL.md" || fail "eval 1: Codex skill copy missing"
[[ -z "$(git -C "$tmp/e1" status --porcelain)" ]] || fail "eval 1: sandbox should start clean"

bash "$setup" "$tmp/e2" 2 >"$log" 2>&1 || fail "setup eval 2"
test ! -e "$tmp/e2/.claude" || fail "eval 2 without --with-skill must not install the skill"

bash "$setup" "$tmp/e3" 3 --with-skill "$skill" >"$log" 2>&1 || fail "setup eval 3"
[[ "$(git -C "$tmp/e3-fix-loops" status --porcelain | sort | tr '\n' ' ')" == " M README.md  M src/retry.py " ]] \
  || fail "eval 3: worktree must change exactly README.md and src/retry.py"
test -f "$tmp/e3-fix-loops-report.md" || fail "eval 3: report missing"

bash "$setup" "$tmp/e4" 4 --with-skill "$skill" >"$log" 2>&1 || fail "setup eval 4"
test -f "$tmp/e4/src/retry.py" || fail "eval 4: src/retry.py missing"
test -x "$tmp/e4/.claude/skills/herdr-orch/scripts/wait-turn.sh" || fail "eval 4: watcher missing from the skill copy"
[[ -z "$(git -C "$tmp/e4" status --porcelain)" ]] || fail "eval 4: sandbox should start clean"
test ! -e "$tmp/e4-fix-loops" || fail "eval 4 must not create eval 3's worktree"

if bash "$setup" "$tmp/e5" 5 >"$log" 2>&1; then fail "setup must refuse an unknown eval id"; fi
grep -q "^setup.sh: unknown eval id: 5$" "$log" || fail "setup refused id 5 for the wrong reason"

if bash "$setup" "$tmp/e1" 1 >"$log" 2>&1; then fail "setup must refuse an existing dir"; fi
grep -q "^setup.sh: $tmp/e1 already exists$" "$log" || fail "setup refused an existing dir for the wrong reason"

echo "ok"
