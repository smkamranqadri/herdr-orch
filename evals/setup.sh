#!/usr/bin/env bash
# Build a fictional sandbox repo for one herdr-orch eval run.
# Usage: setup.sh <new-dir> <eval-id 1|2|3|4> [--with-skill <skill-dir>]
# Eval 4 (idle-finish) uses the same sandbox as eval 2 (stale-done).
set -euo pipefail

dir="${1:?new sandbox dir}"
eval_id="${2:?eval id}"
skill_dir=""
if [[ "${3:-}" == "--with-skill" ]]; then
  skill_dir="${4:?skill dir}"
fi

[[ "$eval_id" =~ ^[1-4]$ ]] || { echo "setup.sh: unknown eval id: $eval_id" >&2; exit 1; }
[[ -e "$dir" ]] && { echo "setup.sh: $dir already exists" >&2; exit 1; }
mkdir -p "$dir/src" "$dir/tests"
cd "$dir"

cat > src/retry.py <<'EOF'
"""Retry helpers for the fictional Lumenfield client."""
import random
import time


def backoff_delay(attempt, base=0.1, cap=2.0):
    return min(cap, base * (2 ** attempt)) * random.uniform(0.5, 1.0)


def retry(fn, attempts=3, sleep=time.sleep):
    for attempt in range(attempts):
        try:
            return fn()
        except ConnectionError:
            if attempt == attempts - 1:
                raise
            sleep(backoff_delay(attempt))
EOF

cat > tests/test_retry.py <<'EOF'
import random

from src.retry import backoff_delay


def test_backoff_delay_is_capped():
    # Flaky: depends on unseeded jitter.
    assert backoff_delay(10) > 1.5
EOF

cat > README.md <<'EOF'
# Lumenfield client

A fictional client used only to test the herdr-orch skill.
EOF

git init -q -b main
git -c user.name=eval -c user.email=eval@example.invalid add -A
git -c user.name=eval -c user.email=eval@example.invalid commit -qm "Initial sandbox"

if [[ -n "$skill_dir" ]]; then
  mkdir -p .claude/skills .agents/skills
  cp -R "$skill_dir" .claude/skills/herdr-orch
  cp -R "$skill_dir" .agents/skills/herdr-orch
  rm -rf .claude/skills/herdr-orch/evals .agents/skills/herdr-orch/evals \
    .claude/skills/herdr-orch/.git .agents/skills/herdr-orch/.git
  printf '.claude/\n.agents/\n' >> .git/info/exclude
fi

if [[ "$eval_id" == "3" ]]; then
  git worktree add -q -b fix-loops "../$(basename "$dir")-fix-loops"
  wt="../$(basename "$dir")-fix-loops"
  sed -i 's/random.uniform(0.5, 1.0)/random.uniform(0.75, 1.0)/' "$wt/src/retry.py"
  printf '\nRetries now use a narrower jitter band.\n' >> "$wt/README.md"
  cat > "../$(basename "$dir")-fix-loops-report.md" <<'EOF'
# fix-loops report

Claimed files: src/retry.py, tests/test_retry.py
Change: narrowed the jitter band in backoff_delay so the cap test is stable.
Tests: python -m pytest tests -q -> 1 passed
EOF
fi

echo "sandbox ready: $dir"
