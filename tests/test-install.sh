#!/usr/bin/env bash
# Installer tests in a temporary HOME. Never touches the real ~/.agents or ~/.claude.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
home="$tmp/home"; mkdir -p "$home"
log="$tmp/log"

fail() { echo "FAIL: $*" >&2; echo "--- last output ---" >&2; cat "$log" >&2 || true; exit 1; }

# 1. install
"$repo_root/bootstrap.sh" install --source "$repo_root" --home "$home" >"$log" 2>&1 || fail "install exited non-zero"
grep -q "^Installed herdr-orch 0" "$log" || fail "install did not report herdr-orch"
test -f "$home/.agents/skills/herdr-orch/SKILL.md" || fail "SKILL.md missing"
test -f "$home/.agents/skills/herdr-orch/references/plan-mode.md" || fail "references missing"
[[ "$(readlink "$home/.claude/skills/herdr-orch")" == "../../.agents/skills/herdr-orch" ]] || fail "Claude link missing or wrong"
test -f "$home/.claude/skills/herdr-orch/SKILL.md" || fail "Claude link does not resolve"
test ! -e "$home/.agents/skills/herdr-orch/evals" || fail "evals must not be installed"
test ! -e "$home/.agents/skills/herdr-orch/tests" || fail "tests must not be installed"
test ! -e "$home/.gemini" || fail "install created ~/.gemini for a host that is not set up"

# 2. byte-identical to source
diff -r --exclude=__pycache__ --exclude=.DS_Store "$repo_root/skills/herdr-orch" "$home/.agents/skills/herdr-orch" >"$log" 2>&1 \
  || fail "installed skill differs from source"

# 3. a second install refuses without --force
if "$repo_root/bootstrap.sh" install --source "$repo_root" --home "$home" >"$log" 2>&1; then fail "second install should refuse"; fi
grep -q "install already exists" "$log" || fail "second install gave the wrong reason"

# 4. check reports current, then differs after a local edit; update restores it with a backup
"$repo_root/bootstrap.sh" check --source "$repo_root" --home "$home" >"$log" 2>&1 || fail "check on a fresh install should pass"
grep -q "^Already current: herdr-orch$" "$log" || fail "check did not report current"
echo "local edit" >> "$home/.agents/skills/herdr-orch/SKILL.md"
if "$repo_root/bootstrap.sh" check --source "$repo_root" --home "$home" >"$log" 2>&1; then fail "check should fail after an edit"; fi
grep -q "^Update available: herdr-orch" "$log" || fail "check did not report the difference"
"$repo_root/bootstrap.sh" update --source "$repo_root" --home "$home" >"$log" 2>&1 || fail "update exited non-zero"
ls "$home/.agents/"herdr-orch-backup-*.tgz >/dev/null 2>&1 || fail "update kept no backup"
diff -r "$repo_root/skills/herdr-orch" "$home/.agents/skills/herdr-orch" >"$log" 2>&1 || fail "update did not restore the source"

# 5. a user's own path at the Claude link is kept, even under --force
userhome="$tmp/userhome"; mkdir -p "$userhome/.claude/skills/herdr-orch"; echo mine > "$userhome/.claude/skills/herdr-orch/own.md"
"$repo_root/bootstrap.sh" install --source "$repo_root" --home "$userhome" --force >"$log" 2>&1 || fail "install over a user path exited non-zero"
grep -q "Kept your existing Claude skill path" "$log" || fail "a user Claude path was not reported as kept"
test -f "$userhome/.claude/skills/herdr-orch/own.md" || fail "a user Claude path was overwritten"

# 6. with agy set up, its skills folder gets a link
agyhome="$tmp/agyhome"; mkdir -p "$agyhome/.gemini"
"$repo_root/bootstrap.sh" install --source "$repo_root" --home "$agyhome" >"$log" 2>&1 || fail "install with agy exited non-zero"
[[ "$(readlink "$agyhome/.gemini/config/skills/herdr-orch")" == "../../../.agents/skills/herdr-orch" ]] || fail "agy link missing or wrong"

# 7. --no-claude-link leaves ~/.claude alone
nolink="$tmp/nolink"
"$repo_root/bootstrap.sh" install --source "$repo_root" --home "$nolink" --no-claude-link >"$log" 2>&1 || fail "install --no-claude-link exited non-zero"
test ! -e "$nolink/.claude" || fail "--no-claude-link created ~/.claude"

echo "ok"
