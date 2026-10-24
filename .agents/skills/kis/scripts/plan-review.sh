#!/usr/bin/env bash
# Plan review guard: a written plan in kis/intent/ carries a "## Review" section that records who
# reviewed it and the plan hash at that time. Read-only; writes nothing.
#   plan-review.sh hash <plan-file>    print the 12-hex plan hash
#   plan-review.sh check <plan-file>   exit 0 and print "Plan review: ok (<date> by <who>)" when the
#                                      last "Reviewed:" line is valid, matches the current hash and
#                                      no finding is open; otherwise exit 1 and print one
#                                      "Plan review: <reason>" line. Missing file: exit 2.
# The hash covers the plan's substance only. Before hashing it drops the last "## Review" section
# outside code fences (to the next "## " heading or the end), every "Status:" line, and blank lines; it normalises [x]/[X]
# checkboxes to [ ] and strips trailing whitespace. Marking work done keeps a review valid.
set -euo pipefail

usage() { echo "Usage: plan-review.sh hash|check <plan-file>" >&2; exit 2; }
[[ $# -eq 2 ]] || usage
cmd="$1"; plan="$2"
[[ "$cmd" == "hash" || "$cmd" == "check" ]] || usage
[[ -f "$plan" ]] || { echo "Error: plan file not found: $plan" >&2; exit 2; }

# One awk pass shared by the three views of the plan. Headings inside ``` or ~~~ fences are not
# headings. The Review section starts at the LAST "## Review" heading outside fences (an earlier
# one is ordinary plan text) and ends at the next "## " heading or the end.
#   mode=start    print the line number of that heading (0 when there is none)
#   mode=section  print the lines of the Review section, heading excluded (needs -v start=N)
#   mode=body     print the plan with progress and the Review section removed (needs -v start=N)
# Known limit, accepted: text on a "Status:" line counts as progress and is not hashed.
plan_awk() {
  awk -v mode="$1" -v start="${2:-0}" '
    {
      line = $0; fl = 0
      sub(/\r$/, "", line)
      if (match(line, /^[ \t]*(```|~~~)/)) {
        c = substr(line, RSTART + RLENGTH - 3, 1)
        if (fence == "") { fence = c; fl = 1 } else if (fence == c) { fence = ""; fl = 1 }
      }
      heading = (fence == "" && !fl && line ~ /^## /)
      if (mode == "start") { if (heading && line ~ /^## Review[ \t]*$/) last = NR; next }
      if (NR == start) { insec = 1; next }
      if (insec && heading) insec = 0
      if (insec) { if (mode == "section") print line; next }
      if (mode != "body") next
      if (line ~ /^[ \t]*([-*][ \t]+)?Status:/) next
      gsub(/\[[xX]\]/, "[ ]", line)
      sub(/[ \t]+$/, "", line)
      if (line != "") print line
    }
    END { if (mode == "start") print last + 0 }
  ' "$plan"
}
review_start="$(plan_awk start)"
review_section() { plan_awk section "$review_start"; }
normalise() { plan_awk body "$review_start"; }

# The git blob id (SHA-1 of "blob <len>\0<text>") of the normalised plan, so it is the same on
# every host. sha1sum or shasum is used first: `git hash-object` in a SHA-256 repository returns
# a SHA-256 id, so git is only the fallback, run outside any repository (cd /) to stay SHA-1.
plan_hash() {
  local text h len
  text="$(normalise)"
  len="$(printf '%s\n' "$text" | wc -c | tr -d ' ')"
  if command -v sha1sum >/dev/null 2>&1; then
    h="$({ printf 'blob %s\0' "$len"; printf '%s\n' "$text"; } | sha1sum | cut -d' ' -f1)"
  elif command -v shasum >/dev/null 2>&1; then
    h="$({ printf 'blob %s\0' "$len"; printf '%s\n' "$text"; } | shasum -a 1 | cut -d' ' -f1)"
  else
    h="$(printf '%s\n' "$text" | (cd / && git hash-object --stdin))"
  fi
  printf '%s\n' "${h:0:12}"
}

if [[ "$cmd" == "hash" ]]; then
  plan_hash
  exit 0
fi

bullet='^[[:space:]]*([-*][[:space:]]+)?'
re_reviewed="${bullet}Reviewed:"
re_by="${bullet}Reviewed:[[:space:]]+([0-9]{4}-[0-9]{2}-[0-9]{2})[[:space:]]+by[[:space:]]+(.+);[[:space:]]+plan hash[[:space:]]+([0-9a-f]{12})[[:space:]]*\$"
re_waived="${bullet}Reviewed:[[:space:]]+waived by the owner[[:space:]]+([0-9]{4}-[0-9]{2}-[0-9]{2});[[:space:]]+plan hash[[:space:]]+([0-9a-f]{12})[[:space:]]*\$"
re_open="${bullet}\\[open\\]"
re_item="${bullet}(Reviewed:|\\[(fixed|rejected|open)\\])"
re_marker='^[[:space:]]+([-*+]|[0-9]+[.)])([[:space:]]|$)'

fail() { echo "Plan review: $1"; exit 1; }

section="$(review_section)"

# The Review section is unhashed, so it may hold nothing but Reviewed lines, findings (each may wrap
# onto indented continuation lines) and blank lines; anything else could smuggle in plan content.
# A continuation line is wrapped prose, so one that starts with a list marker is a hidden item.
in_item=0
while IFS= read -r l || [[ -n "$l" ]]; do
  l="${l%$'\r'}"
  if [[ -z "${l//[[:space:]]/}" ]]; then continue
  elif [[ "$l" =~ $re_item ]]; then in_item=1
  elif (( in_item )) && [[ "$l" =~ ^[[:space:]] && ! "$l" =~ $re_marker ]]; then continue
  else fail "unexpected line in the Review section: ${l:0:80}"
  fi
done <<< "$section"

last="$(printf '%s\n' "$section" | grep -E "$re_reviewed" | tail -n 1 || true)"
[[ -n "$last" ]] || fail "no review recorded"

if [[ "$last" =~ $re_by ]]; then
  date="${BASH_REMATCH[2]}"; who="by ${BASH_REMATCH[3]}"; recorded="${BASH_REMATCH[4]}"
elif [[ "$last" =~ $re_waived ]]; then
  date="${BASH_REMATCH[2]}"; who="waived by the owner"; recorded="${BASH_REMATCH[3]}"
else
  fail "malformed review line"
fi

current="$(plan_hash)"
[[ "$recorded" == "$current" ]] || fail "changed since the review (hash $recorded, now $current)"

open="$(printf '%s\n' "$section" | grep -cE "$re_open" || true)"
(( open == 0 )) || fail "$open open finding(s)"

echo "Plan review: ok ($date $who)"
