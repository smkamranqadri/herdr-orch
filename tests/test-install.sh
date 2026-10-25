#!/usr/bin/env bash
# Installer tests in a temporary HOME. Never touches the real ~/.agents or ~/.claude.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
home="$tmp/home"; mkdir -p "$home"
log="$tmp/log"

fail() { echo "FAIL: $*" >&2; echo "--- last output ---" >&2; cat "$log" >&2 || true; exit 1; }
# Runs bootstrap.sh with no controlling terminal, so the auto-mode question can never prompt.
bs() { setsid -w "$repo_root/bootstrap.sh" "$@" </dev/null; }

# 1. install
bs install --source "$repo_root" --home "$home" >"$log" 2>&1 || fail "install exited non-zero"
grep -q "^Installed herdr-orch 0" "$log" || fail "install did not report herdr-orch"
test -f "$home/.agents/skills/herdr-orch/SKILL.md" || fail "SKILL.md missing"
test -x "$home/.agents/skills/herdr-orch/scripts/wait-turn.sh" || fail "watcher script missing or not executable"
[[ "$(readlink "$home/.claude/skills/herdr-orch")" == "../../.agents/skills/herdr-orch" ]] || fail "Claude link missing or wrong"
test -f "$home/.claude/skills/herdr-orch/SKILL.md" || fail "Claude link does not resolve"
test ! -e "$home/.agents/skills/herdr-orch/evals" || fail "evals must not be installed"
test ! -e "$home/.agents/skills/herdr-orch/tests" || fail "tests must not be installed"
test ! -e "$home/.gemini" || fail "install created ~/.gemini for a host that is not set up"

# 2. byte-identical to source
diff -r --exclude=__pycache__ --exclude=.DS_Store "$repo_root/skills/herdr-orch" "$home/.agents/skills/herdr-orch" >"$log" 2>&1 \
  || fail "installed skill differs from source"

# 3. a second install refuses without --force
if bs install --source "$repo_root" --home "$home" >"$log" 2>&1; then fail "second install should refuse"; fi
grep -q "install already exists" "$log" || fail "second install gave the wrong reason"

# 4. check reports current, then differs after a local edit; update restores it with a backup
bs check --source "$repo_root" --home "$home" >"$log" 2>&1 || fail "check on a fresh install should pass"
grep -q "^Already current: herdr-orch$" "$log" || fail "check did not report current"
echo "local edit" >> "$home/.agents/skills/herdr-orch/SKILL.md"
if bs check --source "$repo_root" --home "$home" >"$log" 2>&1; then fail "check should fail after an edit"; fi
grep -q "^Update available: herdr-orch" "$log" || fail "check did not report the difference"
bs update --source "$repo_root" --home "$home" >"$log" 2>&1 || fail "update exited non-zero"
ls "$home/.agents/"herdr-orch-backup-*.tgz >/dev/null 2>&1 || fail "update kept no backup"
diff -r "$repo_root/skills/herdr-orch" "$home/.agents/skills/herdr-orch" >"$log" 2>&1 || fail "update did not restore the source"

# 5. a user's own path at the Claude link is kept, even under --force
userhome="$tmp/userhome"; mkdir -p "$userhome/.claude/skills/herdr-orch"; echo mine > "$userhome/.claude/skills/herdr-orch/own.md"
bs install --source "$repo_root" --home "$userhome" --force >"$log" 2>&1 || fail "install over a user path exited non-zero"
grep -q "Kept your existing Claude skill path" "$log" || fail "a user Claude path was not reported as kept"
test -f "$userhome/.claude/skills/herdr-orch/own.md" || fail "a user Claude path was overwritten"

# 6. with agy set up, its skills folder gets a link
agyhome="$tmp/agyhome"; mkdir -p "$agyhome/.gemini"
bs install --source "$repo_root" --home "$agyhome" >"$log" 2>&1 || fail "install with agy exited non-zero"
[[ "$(readlink "$agyhome/.gemini/config/skills/herdr-orch")" == "../../../.agents/skills/herdr-orch" ]] || fail "agy link missing or wrong"

# 7. --no-claude-link leaves ~/.claude alone
nolink="$tmp/nolink"
bs install --source "$repo_root" --home "$nolink" --no-claude-link >"$log" 2>&1 || fail "install --no-claude-link exited non-zero"
test ! -e "$nolink/.claude" || fail "--no-claude-link created ~/.claude"

# 8. auto-mode rule: yes adds it after "$defaults", keeps a backup and every other key
am="$tmp/amhome"; mkdir -p "$am/.claude"; st="$am/.claude/settings.json"
printf '{\n  "theme": "auto",\n  "permissions": {\n    "allow": ["Bash(ls)"]\n  }\n}\n' > "$st"
chmod 600 "$st"; cp "$st" "$tmp/st.orig"
bs install --source "$repo_root" --home "$am" --claude-automode yes >"$log" 2>&1 || fail "automode yes exited non-zero"
grep -q "^Added the herdr-orch auto-mode rule to " "$log" || fail "automode yes did not report the rule"
ls "$st".bak-herdr-orch-* >/dev/null 2>&1 || fail "automode yes kept no backup"
cmp -s "$tmp/st.orig" "$(ls "$st".bak-herdr-orch-* | head -1)" || fail "automode backup differs from the original"
ruby -rjson -e '
  d = JSON.parse(File.read(ARGV[0])); a = d["autoMode"]["allow"]
  abort("allow must be $defaults then the rule, got #{a.inspect}") unless a.size == 2 && a[0] == "$defaults" && a[1].start_with?("herdr-orch worker launches:")
  abort("other keys changed") unless d.reject { |k, _| k == "autoMode" } == {"theme" => "auto", "permissions" => {"allow" => ["Bash(ls)"]}}
' "$st" || fail "automode yes wrote the wrong settings"
[[ "$(stat -c %a "$st")" == 600 ]] || fail "automode yes changed the file mode"
cp "$st" "$tmp/st.added"

# 9. a re-run changes nothing
bs update --source "$repo_root" --home "$am" --claude-automode yes >"$log" 2>&1 || fail "automode re-run exited non-zero"
grep -q "^Claude auto-mode rule already present: " "$log" || fail "automode re-run did not report the rule as present"
cmp -s "$st" "$tmp/st.added" || fail "automode re-run changed the file"

# 10. the old throwaway rule is replaced, not kept beside the new one
ruby -rjson -e 'd = JSON.parse(File.read(ARGV[0])); d["autoMode"]["allow"][1] = "Herdr worker launches: old text"; File.write(ARGV[0], JSON.pretty_generate(d))' "$st"
bs update --source "$repo_root" --home "$am" --claude-automode yes >"$log" 2>&1 || fail "automode replace exited non-zero"
cmp -s "$st" "$tmp/st.added" || fail "the old rule was not replaced by exactly the new one"

# 11. no leaves the file byte-identical
cp "$tmp/st.orig" "$st"
bs update --source "$repo_root" --home "$am" --claude-automode no >"$log" 2>&1 || fail "automode no exited non-zero"
cmp -s "$st" "$tmp/st.orig" || fail "automode no changed the file"

# 12. no terminal and no flag: untouched, with the hint
bs update --source "$repo_root" --home "$am" >"$log" 2>&1 || fail "automode no-terminal exited non-zero"
grep -q "^Claude Code auto mode blocks worker launches; to allow them, re-run with --claude-automode yes$" "$log" || fail "no-terminal hint missing"
cmp -s "$st" "$tmp/st.orig" || fail "no-terminal run changed the file"

# 13. invalid JSON and a non-list allow are errors and leave the file untouched
for bad in '{"theme": ' '{"autoMode": {"allow": "x"}}'; do
  printf '%s' "$bad" > "$st"; cp "$st" "$tmp/st.bad"
  if bs update --source "$repo_root" --home "$am" --claude-automode yes >"$log" 2>&1; then fail "bad settings should fail: $bad"; fi
  grep -q "left unchanged" "$log" || fail "bad settings gave the wrong reason: $bad"
  cmp -s "$st" "$tmp/st.bad" || fail "bad settings were changed: $bad"
done

# 14. an existing allow list without "$defaults" gets none
printf '{"autoMode": {"allow": ["Mine"]}}' > "$st"
bs update --source "$repo_root" --home "$am" --claude-automode yes >"$log" 2>&1 || fail "automode own-list exited non-zero"
ruby -rjson -e 'a = JSON.parse(File.read(ARGV[0]))["autoMode"]["allow"]; abort(a.inspect) unless a.size == 2 && a[0] == "Mine" && a[1].start_with?("herdr-orch worker launches:")' "$st" \
  || fail "an existing allow list was not kept as it was"

# 15. a symlinked settings.json is written through, and stays a link
mkdir -p "$tmp/dotfiles"; printf '{}' > "$tmp/dotfiles/settings.json"; ln -sf "$tmp/dotfiles/settings.json" "$st"
bs update --source "$repo_root" --home "$am" --claude-automode yes >"$log" 2>&1 || fail "automode symlink exited non-zero"
test -L "$st" || fail "the settings symlink was replaced by a file"
grep -q "herdr-orch worker launches:" "$tmp/dotfiles/settings.json" || fail "the symlink target did not get the rule"

# 16. no ~/.claude before the install: no question, no settings file
fresh="$tmp/fresh"
bs install --source "$repo_root" --home "$fresh" --claude-automode yes >"$log" 2>&1 || fail "automode fresh home exited non-zero"
test ! -e "$fresh/.claude/settings.json" || fail "a home with no ~/.claude got a settings file"
if grep -qi "auto mode\|auto-mode" "$log"; then fail "a home with no ~/.claude was asked about auto mode"; fi

echo "ok"
