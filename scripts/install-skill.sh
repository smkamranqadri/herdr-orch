#!/usr/bin/env bash
# Install skills/<name>/ from a source clone into ~/.agents/skills/<name> and link it for
# Claude Code (and agy, when it is set up). Run from a source clone only.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  install-skill.sh --source <repo-root> [--home <dir>] [--force] [--no-claude-link]

Options:
  --source <path>    Source repo root containing skills/<name>/SKILL.md. Also HERDR_ORCH_SOURCE.
  --home <dir>       Home directory to install into. Defaults to $HOME.
  --force            Replace an existing ~/.agents/skills/<name> (a .tgz backup is kept).
  --no-claude-link   Do not create the ~/.claude/skills/<name> link.
  -h, --help         Show this help.
USAGE
}

die() { echo "Error: $*" >&2; exit 1; }

source_arg="${HERDR_ORCH_SOURCE:-}"
home_dir="${HOME:-}"
force="false"
claude_link="true"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source) [[ $# -ge 2 ]] || die "--source requires a path"; source_arg="$2"; shift 2 ;;
    --home) [[ $# -ge 2 ]] || die "--home requires a path"; home_dir="$2"; shift 2 ;;
    --force) force="true"; shift ;;
    --no-claude-link) claude_link="false"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -n "$source_arg" ]] || die "missing --source <repo-root> or HERDR_ORCH_SOURCE"
[[ -n "$home_dir" ]] || die "missing --home <dir> and HOME is unset"
[[ -d "$source_arg/skills" ]] || die "source is not a herdr-orch repo root (no skills/): $source_arg"
source_root="$(cd "$source_arg" && pwd -P)"
home_dir="$(mkdir -p "$home_dir" && cd "$home_dir" && pwd -P)"

read_version() {
  ruby -ryaml -e '
    text = File.read(File.join(ARGV.fetch(0), "SKILL.md"))
    fm = text[/\A---\n(.*?)\n---\n/m, 1] or abort("missing YAML frontmatter in #{ARGV[0]}/SKILL.md")
    data = YAML.safe_load(fm)
    abort("frontmatter must be a map") unless data.is_a?(Hash)
    abort("missing name") if data["name"].to_s.strip.empty?
    abort("invalid name") unless data["name"].match?(/\A[a-z0-9-]+\z/)
    abort("missing description") if data["description"].to_s.strip.empty?
    v = data.dig("metadata", "version")
    abort("missing metadata.version in #{ARGV[0]}/SKILL.md") if v.to_s.strip.empty?
    puts v
  ' "$1"
}

# Link ~/<dir>/<name> to the installed copy. A correct link is left alone; anything else at that
# path is the user's and is kept and reported, even under --force.
link_skill() {
  local label="$1" link="$2" target="$3"
  mkdir -p "$(dirname "$link")"
  if [[ -L "$link" ]] && [[ "$(readlink "$link")" == "$target" ]]; then
    echo "$label skill link already current: $link"
  elif [[ -e "$link" || -L "$link" ]]; then
    echo "Kept your existing $label skill path: $link (not overwritten)"
  else
    ln -s "$target" "$link"
    echo "$label skill link: $link -> $target"
  fi
}

skills_dir="$home_dir/.agents/skills"
mkdir -p "$skills_dir"

for src in "$source_root"/skills/*/; do
  name="$(basename "$src")"
  [[ -f "$src/SKILL.md" ]] || die "skills/$name has no SKILL.md"
  version="$(read_version "$src")"
  dest="$skills_dir/$name"
  if [[ -e "$dest" || -L "$dest" ]]; then
    [[ "$force" == "true" ]] || die "install already exists at $dest; use --force to replace it, or bootstrap.sh update"
    backup="$home_dir/.agents/$name-backup-$(date +%Y%m%d-%H%M%S).tgz"
    tar -czf "$backup" -C "$skills_dir" "$name"
    rm -rf "$dest"
    echo "Backed up previous $name to $backup"
  fi
  tmp="$(mktemp -d)"
  cp -R "$src" "$tmp/$name"
  find "$tmp/$name" -name __pycache__ -type d -prune -exec rm -rf {} +
  find "$tmp/$name" -name .DS_Store -delete
  mv "$tmp/$name" "$dest"
  rmdir "$tmp"
  echo "Installed $name $version -> $dest"
  if [[ "$claude_link" == "true" ]]; then
    link_skill Claude "$home_dir/.claude/skills/$name" "../../.agents/skills/$name"
  fi
  # agy reads global skills only from ~/.gemini/config/skills/; link there when agy is set up.
  if [[ -d "$home_dir/.gemini" ]]; then
    link_skill agy "$home_dir/.gemini/config/skills/$name" "../../../.agents/skills/$name"
  fi
done
