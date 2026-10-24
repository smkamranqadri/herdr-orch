#!/usr/bin/env bash
set -euo pipefail

project_root="${1:-${CLAUDE_PROJECT_DIR:-$PWD}}"
kis_dir="$project_root/kis"
# The anchor is loaded at every session start, resume, clear and compact, so it must stay small.
# KIS_ANCHOR_MAX_LINES is the whole-anchor line budget, stated here and in the tool's env docs;
# the output below is built to fit it (minimum 18, the header, the optional Stale State line, the
# five summary fields and the pointer), and a State with no summary fields gets a capped head
# instead of the whole file.
max_lines="${KIS_ANCHOR_MAX_LINES:-20}"
# A summary field (its label plus its indented continuation lines) is joined and then cut at
# this many bytes, backed off to a character boundary, "..." marking the cut. The full value is in the State file it points at.
max_field_chars="${KIS_ANCHOR_MAX_FIELD_CHARS:-200}"
[[ "$max_lines" =~ ^[0-9]+$ ]] || max_lines=20
[[ "$max_lines" -lt 18 ]] && max_lines=18
[[ "$max_field_chars" =~ ^[0-9]+$ ]] || max_field_chars=200

printed=0
p() { echo "$@"; printed=$((printed + 1)); }

p "# KIS Anchor"
p
p "This project uses KIS project memory under \`kis/\`. Knowledge = stable facts. Intent = goals and plans. State = current reality."
p "Load State first, put each fact in one layer, prove work before marking it done, and synchronize only what changed."
p "Skill: .agents/skills/kis/SKILL.md"
p "Commands in .agents/skills/kis/commands/: start, plan, act, sync, check, init."
p "Claude /kis:start, Pi and OpenCode /kis-start, Codex /prompts:kis-start. Antigravity has no custom slash commands: name the step instead."
p

if [[ ! -d "$kis_dir" ]]; then
  p "KIS is not initialized in this project. Run the init command before non-trivial work."
  exit 0
fi

state_file=""
if [[ -f "$kis_dir/state/current.md" ]]; then
  state_file="$kis_dir/state/current.md"
else
  while IFS= read -r candidate; do
    state_file="$candidate"
    break
  done < <(find "$kis_dir/state" -maxdepth 1 -type f -name '*.md' 2>/dev/null | sort)
fi

if [[ -z "$state_file" ]]; then
  p "No State file found under kis/state/. Recover context with the start command."
  exit 0
fi

rel="${state_file#"$project_root/"}"
total_lines="$(wc -l < "$state_file" | tr -d ' ')"
other_state="$(find "$kis_dir/state" -maxdepth 1 -type f -name '*.md' ! -path "$state_file" 2>/dev/null | sort | sed "s|^$project_root/||")"

p "## Current State: $rel"
p

# One line when the code outside kis/ moved on since the last sync; silent otherwise.
stamp_helper="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../scripts/state-stamp.sh"
stale_line=""
# The helper time-caps itself (5 seconds for --check, with or without `timeout`), so a huge
# untracked tree cannot stall the session start; past the cap the line is simply absent.
if [[ -f "$stamp_helper" ]]; then
  stale_line="$(bash "$stamp_helper" --check "$project_root" 2>/dev/null | head -n 1 || true)"
fi
[[ -n "$stale_line" ]] && p "$stale_line"

# The awk runs under LC_ALL=C: a UTF-8 gawk skips any line holding an invalid byte, which would lose
# the summary. In C, length and substr count bytes, so ucut() backs off while the next byte is a
# UTF-8 continuation byte (0x80-0xBF) and never splits a multibyte character.
awk_lib='function ucut(s, n,   i, c) {
  if (n >= length(s)) return s
  if (n < 0) n = 0
  if (!built) { for (i = 128; i < 192; i++) cont[sprintf("%c", i)] = 1; built = 1 }
  while (n > 0 && (substr(s, n + 1, 1) in cont)) n--
  return substr(s, 1, n)
}
'

# A short summary of the five recovery fields, never the whole file. Branch, Run, Task, Blocker
# and Next come from a `Label:` line (any bullet marker, indented continuation lines joined, capped
# at max_field_chars). When a label is absent, Next falls back to the first item under a
# `## Next` heading and Blocker to the first item under a `## Open` heading: the shape real
# State files use.
summary="$(LC_ALL=C awk -v max="$max_field_chars" "$awk_lib"'
function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
function add(name, s) {
  s = trim(s)
  gsub(/[[:space:]]+/, " ", s)
  if (s == "" || v[name] != "") return
  v[name] = s
}
function app(name, s) {
  s = trim(s)
  if (s == "") return
  gsub(/[[:space:]]+/, " ", s)
  v[name] = (v[name] == "" ? s : v[name] " " s)
}
{
  line = $0
  if (line ~ /^##[[:space:]]/) { heading = trim(line); cur = ""; next }
  if (line ~ /^[[:space:]]*[-*]?[[:space:]]*(Branch|Run|Task|Blocker|Next)[[:space:]]*:/) {
    n = line
    sub(/^[[:space:]]*[-*]?[[:space:]]*/, "", n)
    name = n; sub(/[[:space:]]*:.*/, "", name)
    val = n; sub(/^[^:]*:[[:space:]]*/, "", val)
    cur = name
    add(name, val)
    next
  }
  if (cur != "" && line ~ /^[[:space:]]*$/) { cur = ""; next }
  if (cur != "" && line ~ /^[[:space:]]/) { app(cur, line); next }
  if (cur != "") cur = ""
  slot = (heading == "## Next" ? "Next" : heading == "## Open" ? "Blocker" : "")
  if (slot != "" && v[slot] == "" && line ~ /^[[:space:]]*([-*]|[0-9]+[.)])[[:space:]]/) {
    item = line
    sub(/^[[:space:]]*([-*]|[0-9]+[.)])[[:space:]]*/, "", item)
    cur = slot
    add(slot, item)
  }
}
END {
  order[1] = "Branch"; order[2] = "Run"; order[3] = "Task"; order[4] = "Blocker"; order[5] = "Next"
  for (i = 1; i <= 5; i++) {
    n = order[i]
    if (v[n] == "") continue
    s = v[n]
    if (length(s) > max) {
      # The Run pointer is the part the anchor exists to show: keep "; live record at <path>" whole
      # and shorten the description before it.
      tag = "; live record at "
      cut = 0; pos = 0; rest = s
      while ((k = index(rest, tag)) > 0) { cut = pos + k; pos = cut + length(tag) - 1; rest = substr(s, pos + 1) }
      if (n == "Run" && cut > 0) {
        tail = substr(s, cut)
        keep = max - length(tail) - 3
        s = (keep >= 1 ? ucut(s, keep) : "") "..." tail
      } else {
        s = ucut(s, max - 3) "..."
      }
    }
    print n ": " s
  }
}
' "$state_file")"

other_lines=0
[[ -n "$other_state" ]] && other_lines=1

if [[ -n "$summary" ]]; then
  printf '%s\n' "$summary"
  printed=$((printed + $(printf '%s\n' "$summary" | wc -l | tr -d ' ')))
  p
  p "Full State: $rel ($total_lines lines; summary within $max_lines lines) - read it before planning."
else
  # Nothing to summarise: show a head of State that fits the budget, and point at the file.
  room=$((max_lines - printed - 2 - other_lines))
  [[ "$room" -lt 1 ]] && room=1
  head -n "$room" "$state_file" | LC_ALL=C awk -v max="$max_field_chars" "$awk_lib"'{ if (length($0) > max) $0 = ucut($0, max - 3) "..."; print }'
  printed=$((printed + room))
  p
  p "No Branch/Task/Blocker/Next summary fields found; read $rel ($total_lines lines) before planning."
fi

if [[ -n "$other_state" ]] && (( printed + 1 <= max_lines )); then
  p "Other State files: $(printf '%s\n' "$other_state" | paste -sd ', ' -)"
fi
