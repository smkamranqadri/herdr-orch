#!/usr/bin/env bash
# Static checks on the skill package: metadata limits, links, wording, and (when Herdr is
# installed) that every herdr command the skill names exists.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
skill="$repo_root/skills/herdr-orch"

fail() { echo "FAIL: $*" >&2; exit 1; }

# 1. frontmatter and openai.yaml, parsed as YAML
ruby -ryaml -e '
  dir, changelog = ARGV
  text = File.read(File.join(dir, "SKILL.md"))
  fm = text[/\A---\n(.*?)\n---\n/m, 1] or abort("SKILL.md: missing frontmatter")
  d = YAML.safe_load(fm)
  name, desc = d["name"].to_s, d["description"].to_s
  abort("name must be lowercase letters, digits and hyphens, at most 64") unless name.match?(/\A[a-z0-9-]{1,64}\z/)
  abort("name must not contain claude or anthropic") if name.match?(/claude|anthropic/)
  abort("name #{name} must match its folder") unless name == File.basename(dir)
  abort("description must be 1..1024 characters") unless (1..1024).cover?(desc.length)
  abort("description must not contain XML tags") if desc.match?(/<[^>]+>/)
  abort("disable-model-invocation must be true") unless d["disable-model-invocation"] == true
  v = d.dig("metadata", "version").to_s
  abort("missing metadata.version") if v.empty?
  top = File.read(changelog)[/^## (\S+)/, 1]
  abort("CHANGELOG top entry #{top} must match metadata.version #{v}") unless top == v
  body = text.split(/\A---\n.*?\n---\n/m, 2).last
  abort("SKILL.md body must stay under 500 lines") unless body.lines.count < 500
  y = YAML.safe_load(File.read(File.join(dir, "agents", "openai.yaml")))
  abort("openai.yaml display_name must be #{name}") unless y.dig("interface", "display_name") == name
  abort("openai.yaml must disable implicit invocation") unless y.dig("policy", "allow_implicit_invocation") == false
' "$skill" "$repo_root/CHANGELOG.md" || fail "metadata"

# 2. every relative Markdown link in the skill resolves
while IFS= read -r -d '' md; do
  while IFS= read -r target; do
    [[ "$target" =~ ^(https?:|#|mailto:) ]] && continue
    [[ -e "$(dirname "$md")/${target%%#*}" ]] || fail "broken link in ${md#"$repo_root/"}: $target"
  done < <(grep -oE '\]\([^)]+\)' "$md" | sed -E 's/^\]\((.*)\)$/\1/')
done < <(find "$skill" -name '*.md' -print0)

# 3. wording the skill must not carry
if grep -rnE '\brtk\b|\bcontroller\b' "$skill"; then fail "rtk or controller wording found"; fi

# 4. every herdr command the skill names exists in the installed Herdr
if command -v herdr >/dev/null 2>&1; then
  groups=" agent pane tab worktree workspace notification integration "
  while read -r a b; do
    if [[ "$groups" == *" $a "* ]]; then cmd=("$a" "$b"); else cmd=("$a"); fi
    herdr "${cmd[@]}" --help >/dev/null 2>&1 || fail "unknown Herdr command: herdr ${cmd[*]}"
  # Join lines first: a reflowed code span can split `herdr agent` from its subcommand.
  done < <(find "$skill" -name '*.md' -exec cat {} + | tr '\n' ' ' | tr -s ' ' \
    | grep -oE '\bherdr [a-z][a-z-]*( [a-z][a-z-]*)?' | sed 's/^herdr //' \
    | awk '{print $1, ($2 == "" ? "-" : $2)}' | sort -u)
  echo "checked herdr commands against $(herdr --version 2>/dev/null | head -1)"
else
  echo "skipped herdr command check: herdr not installed"
fi

echo "ok"
