#!/usr/bin/env bash
# State stamp: lets a fresh session see code changes made after the last sync.
#   state-stamp.sh [<project-root>]           print "Stamp: <branch> <short-sha> <tree>"
#   state-stamp.sh --check [<project-root>]   print one "Stale State: ..." line when State is
#                                             behind the code, nothing otherwise; always exit 0
# <project-root> defaults to the project this script is installed in (the directory above
# .agents/skills/kis/scripts), else the current directory, so the stamp never depends on the cwd.
# <tree> fingerprints the working-tree content of the project outside kis/ and .orch/ (committed or
# not, tracked or untracked-but-not-ignored), so commits alone never change it. A project that is a
# subdirectory of a repository fingerprints only its own subtree. It is computed read-only: nothing
# is written under .git (no objects, no index, no locks) and no clean/smudge/process filter program
# runs. The computation is time-capped (KIS_STAMP_TIMEOUT_SECONDS, default 5 for --check and 60
# for a stamp); past the cap --check stays quiet and a stamp reports an error. The --check default
# sits well under the 20 s timeout of the Codex and Command Code hook entries, so a slow stamp never
# costs the rest of the anchor.
set -euo pipefail
export GIT_OPTIONAL_LOCKS=0

self="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
script_dir="${self%/*}"
# Run through the .claude/skills/kis link the installer creates, the logical directory does not hold
# .agents; the physical one does. The logical path is tried first, so a package that is itself a
# symlink into another place still resolves.
if [[ "$script_dir" != */.agents/skills/kis/scripts ]]; then
  phys_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  [[ "$phys_dir" != */.agents/skills/kis/scripts ]] || script_dir="$phys_dir"
fi

mode="stamp"
case "${1:-}" in
  --check) mode="check"; shift ;;
  --compute) mode="compute"; shift ;;  # internal: print "<branch> <short-sha> <tree>", uncapped
esac
if [[ $# -ge 1 ]]; then
  project_root="$1"
elif [[ "$script_dir" == */.agents/skills/kis/scripts ]]; then
  project_root="${script_dir%/.agents/skills/kis/scripts}"
  [[ -n "$project_root" ]] || project_root="/"
else
  project_root="$PWD"
fi

tmpdir=""

# Prints "<branch> <short-sha> <tree>"; returns non-zero when it cannot.
# The fingerprint is a hash of the sorted "mode blob-id <TAB> path" lines for every file of the
# project outside kis/ and .orch/: the index entries, overridden by what the working tree holds for
# modified, deleted and untracked (not ignored) paths. Blob ids come from `git hash-object`
# without -w. Records are lines with the path last; git's own C-quoting is used wherever a path is
# handed to or read from git, a newline inside a path is mapped to a control byte that no path in
# the repository contains (see $nl below), so any path is safe.
# Every configured filter driver is blanked on each git call, so no filter program ever runs
# (a file with a clean filter fingerprints as its raw content; eol conversion still applies).
compute() {
  command -v git >/dev/null 2>&1 || return 1
  cd "$project_root" 2>/dev/null || return 1
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1

  local branch sha prefix top
  branch="$(git symbolic-ref --short -q HEAD 2>/dev/null || true)"
  [[ -n "$branch" ]] || branch="detached"
  sha="$(git rev-parse --short HEAD 2>/dev/null || true)"
  [[ -n "$sha" ]] || sha="none"

  prefix="$(git rev-parse --show-prefix)"
  top="$(git rev-parse --show-toplevel)"
  cd "$top" || return 1
  local spec=(".")
  [[ -z "$prefix" ]] || spec=(":(top,literal)${prefix}")
  spec+=(":(top,exclude,literal)${prefix}kis" ":(top,exclude,literal)${prefix}.orch")

  local fopts=(-c core.fsmonitor=false -c core.quotePath=true) rec name
  while IFS= read -r -d '' rec; do
    name="${rec%%$'\n'*}"; name="${name#filter.}"; name="${name%.*}"
    fopts+=(-c "filter.$name.clean=" -c "filter.$name.smudge=" -c "filter.$name.process=" -c "filter.$name.required=false")
  done < <(git config -z --get-regexp '^filter\..+\.(clean|smudge|process)$' 2>/dev/null || true)
  gt() { git "${fopts[@]}" "$@"; }

  local fmode
  fmode="$(git config --bool core.fileMode 2>/dev/null || true)"
  [[ "$fmode" == "false" ]] || fmode=true

  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/kis-stamp.XXXXXX")" || return 1
  trap 'rm -rf "$tmpdir"' EXIT
  trap 'exit 143' TERM INT HUP

  # Candidates: modified, deleted and untracked paths, one per line (a newline in a path becomes
  # $nl, the first control byte that appears in no candidate and no index path, so two paths never
  # share a key). Ordinary paths are classified in bulk by `find` (no per-file shell loop); regular
  # files and symlink targets go to one batched hash, everything else becomes a finished record.
  # Paths that are not line safe (newline, leading quote, trailing CR) take the slow per-file route at
  # the end. Paths with a byte >= 0x80 that are otherwise line safe are classified by a loop of bash
  # builtins (no fork per file) and join the same batches: git on macOS reports a non-ASCII name
  # precomposed (NFC) while `find` prints it as stored (often NFD), so the byte-exact match of the fast
  # route would miss it, but the filesystem lookup there ignores the normalization, so the path git
  # prints opens fine. That macOS case was not run; the routing is covered on Linux.
  gt ls-files -z -m -d -o --exclude-standard -- "${spec[@]}" > "$tmpdir/candz"
  gt ls-files -s -z -- "${spec[@]}" > "$tmpdir/indexz"
  local f odd_re nl n
  nl=$'\001'
  for n in 1 2 3 4 5 6 7 8 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31; do
    nl="$(printf "\\$(printf '%03o' "$n")")"
    LC_ALL=C grep -qa -e "$nl" "$tmpdir/candz" "$tmpdir/indexz" || break
  done
  tr '\n\0' "$nl\n" < "$tmpdir/candz" > "$tmpdir/cand"
  for f in fast types fpaths fmodes records syms dirs; do : > "$tmpdir/$f"; done
  odd_re=(-e "$nl" -e '^"' -e "$(printf '\r')\$")
  hi_re="$(printf '[\200-\377]')"
  : > "$tmpdir/hi"
  LC_ALL=C grep -a "${odd_re[@]}" "$tmpdir/cand" > "$tmpdir/odd" || true
  LC_ALL=C grep -a -v "${odd_re[@]}" "$tmpdir/cand" | LC_ALL=C grep -a -e "$hi_re" > "$tmpdir/hi" || true
  LC_ALL=C grep -a -v "${odd_re[@]}" "$tmpdir/cand" | LC_ALL=C grep -a -v -e "$hi_re" | sed 's|/$||; s|^|./|' > "$tmpdir/fast" || true
  if [[ -s "$tmpdir/fast" ]]; then
    # One find pass over the directories that hold candidates tags every entry: l symlink,
    # d directory, x executable file, f other file. A candidate that is not tagged is gone.
    sed 's|/[^/]*$||' "$tmpdir/fast" | LC_ALL=C sort -u | tr '\n' '\0' |
      xargs -0 sh -c 'find -P "$@" -mindepth 1 -maxdepth 1 \( \
          -type l -exec printf "l %s\n" {} + -o \
          -type d -exec printf "d %s\n" {} + -o \
          -type f -perm -100 -exec printf "x %s\n" {} + -o \
          -type f -exec printf "f %s\n" {} + \)' sh > "$tmpdir/types" 2>/dev/null || true
    # Regular files: path and mode ('?' = take the index mode, used when git ignores the exec bit).
    LC_ALL=C awk -v fm="$fmode" -v syms="$tmpdir/syms" -v dirs="$tmpdir/dirs" -v fpaths="$tmpdir/fpaths" \
        -v fmodes="$tmpdir/fmodes" -v records="$tmpdir/records" '
      FILENAME == ARGV[1] { T[substr($0, 3)] = substr($0, 1, 1); next }
      { p = substr($0, 3); t = T[$0]
        if (t == "l") print p > syms
        else if (t == "d") print p > dirs
        else if (t == "x" || t == "f") { print p > fpaths; print (fm == "false" ? "?" : (t == "x") ? "100755" : "100644") > fmodes }
        else print "DEL\t" p > records
      }' "$tmpdir/types" "$tmpdir/fast"
  fi

  local p k blob fmt
  # Line-safe paths with a high byte: the same classes as the find pass, by builtins, into the same files.
  while IFS= read -r p; do
    p="${p%/}"
    if [[ -L "$p" ]]; then printf '%s\n' "$p" >> "$tmpdir/syms"
    elif [[ -d "$p" ]]; then printf '%s\n' "$p" >> "$tmpdir/dirs"
    elif [[ -f "$p" ]]; then
      printf '%s\n' "$p" >> "$tmpdir/fpaths"
      if [[ "$fmode" == "false" ]]; then fmt='?'; elif [[ -x "$p" ]]; then fmt=100755; else fmt=100644; fi
      printf '%s\n' "$fmt" >> "$tmpdir/fmodes"
    else printf 'DEL\t%s\n' "$p" >> "$tmpdir/records"
    fi
  done < "$tmpdir/hi"
  exec 5>>"$tmpdir/records"
  if [[ -s "$tmpdir/syms" ]]; then  # symlinks: the blob is the link target, hashed in one batch
    # One readlink per batch writes the targets, one per line; awk puts each into its own file and git
    # hashes the files (the blob of a link is its target bytes). A target with a newline, or a link
    # readlink could not read, shifts the lines: the counts then differ and every link goes the slow way.
    mkdir "$tmpdir/lt"
    tr '\n' '\0' < "$tmpdir/syms" | xargs -0 readlink -- 2>/dev/null |
      LC_ALL=C awk -v d="$tmpdir/lt" '{ f = d "/" NR; printf "%s", $0 > f; close(f); print f }' > "$tmpdir/ltpaths" || true
    if [[ "$(wc -l < "$tmpdir/ltpaths" | tr -d ' ')" == "$(wc -l < "$tmpdir/syms" | tr -d ' ')" ]]; then
      gt hash-object --no-filters --stdin-paths < "$tmpdir/ltpaths" > "$tmpdir/lthashes"
      LC_ALL=C awk 'FNR == NR { h[FNR] = $0; next } { print "120000 " h[FNR] "\t" $0 }' "$tmpdir/lthashes" "$tmpdir/syms" >&5
    else
      cat "$tmpdir/syms" >> "$tmpdir/odd"
    fi
  fi
  while IFS= read -r p; do  # a submodule or nested repository records its commit; else it replaced a file
    if [[ -e "$p/.git" ]]; then
      blob="$(git -C "$p" rev-parse HEAD 2>/dev/null)" || blob="none"
      printf '160000 %s\t%s\n' "$blob" "$p" >&5
    else
      printf 'DEL\t%s\n' "$p" >&5
    fi
  done < "$tmpdir/dirs"
  while IFS= read -r k; do  # paths that are not line safe, one by one
    p="${k//$nl/$'\n'}"
    if [[ -L "$p" ]]; then
      blob="$(readlink -n -- "$p" | gt hash-object --stdin)"
      printf '120000 %s\t%s\n' "$blob" "$k" >&5
    elif [[ -d "$p" ]]; then
      if [[ -e "$p/.git" ]]; then
        blob="$(git -C "$p" rev-parse HEAD 2>/dev/null)" || blob="none"
        printf '160000 %s\t%s\n' "$blob" "$k" >&5
      else
        printf 'DEL\t%s\n' "$k" >&5
      fi
    elif [[ -f "$p" ]]; then
      fmt=100644
      if [[ "$fmode" == "false" ]]; then fmt='?'; elif [[ -x "$p" ]]; then fmt=100755; fi
      blob="$(gt hash-object -- "$p")"
      printf '%s %s\t%s\n' "$fmt" "$blob" "$k" >&5
    else
      printf 'DEL\t%s\n' "$k" >&5
    fi
  done < "$tmpdir/odd"
  exec 5>&-

  gt hash-object --stdin-paths < "$tmpdir/fpaths" > "$tmpdir/hashes"
  paste -d ' ' "$tmpdir/fmodes" "$tmpdir/hashes" | paste -d '\t' - "$tmpdir/fpaths" >> "$tmpdir/records"

  # Index entries, overridden by the records above (a DEL record drops the entry).
  local tree
  tree="$(
    tr '\n\0' "$nl\n" < "$tmpdir/indexz" |
      LC_ALL=C awk '
        function fin(h, im) {
          if (substr(h, 1, 1) != "?") return h
          sub(/^\? /, "", h)
          return ((im == "100644" || im == "100755") ? im : "100644") " " h
        }
        FILENAME == ARGV[1] { t = index($0, "\t"); W[substr($0, t + 1)] = substr($0, 1, t - 1); next }
        {
          t = index($0, "\t"); p = substr($0, t + 1)
          split(substr($0, 1, t - 1), a, " ")
          if (p in W) {
            if (!(p in done)) { done[p] = 1; if (W[p] != "DEL") print fin(W[p], a[1]) "\t" p }
            next
          }
          print a[1] " " a[2] "\t" p
        }
        END { for (p in W) if (!(p in done) && W[p] != "DEL") print fin(W[p], "") "\t" p }
      ' "$tmpdir/records" - | LC_ALL=C sort | gt hash-object --stdin
  )" || return 1
  printf '%s %s %s\n' "$branch" "$sha" "${tree:0:12}"
}

# Run a command with a time cap; non-zero when the cap hit (124 with `timeout`, 143 from the watcher).
# Uses `timeout` where it exists, else a background watcher, so a huge untracked tree never stalls a
# session start.
capped() {
  local secs="$1" pid killer rc=0
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@" || return $?
    return 0
  fi
  set -m
  "$@" &
  pid=$!
  set +m
  # The watcher's own sleep dies with it: killing the watcher runs its TERM trap, which kills the sleep.
  (
    sleep "$secs" & sleeper=$!
    trap 'kill "$sleeper" 2>/dev/null; exit 0' TERM
    wait "$sleeper" || exit 0
    kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null
  ) >/dev/null 2>&1 &
  killer=$!
  wait "$pid" || rc=$?
  kill "$killer" 2>/dev/null || true
  wait "$killer" 2>/dev/null || true
  return "$rc"
}

stamp_value() {  # print "<branch> <short-sha> <tree>" under the time cap
  local secs="${KIS_STAMP_TIMEOUT_SECONDS:-$1}"
  [[ "$secs" =~ ^[0-9]+$ && "$secs" -gt 0 ]] || secs="$1"
  # The compute's stderr is dropped: when the cap kills it, bash prints a "Terminated  <pipeline>" notice.
  capped "$secs" "${BASH:-bash}" "$self" --compute "$project_root" 2>/dev/null
}

if [[ "$mode" == "compute" ]]; then
  compute
  exit 0
fi

if [[ "$mode" == "stamp" ]]; then
  current="$(stamp_value 60)" || { echo "Error: cannot compute a stamp for $project_root (git repository required, or the time cap was hit)" >&2; exit 1; }
  echo "Stamp: $current"
  exit 0
fi

# --check: never fail a session start.
state_file=""
if [[ -f "$project_root/kis/state/current.md" ]]; then
  state_file="$project_root/kis/state/current.md"
else
  while IFS= read -r candidate; do
    state_file="$candidate"
    break
  done < <(find "$project_root/kis/state" -maxdepth 1 -type f -name '*.md' 2>/dev/null | sort)
fi
[[ -n "$state_file" ]] || exit 0

# Markdown around the line (bold label, backticked value) is ignored.
stamp_line="$(tr -d '*`' < "$state_file" 2>/dev/null | grep -m1 -E '^[[:space:]]*(-[[:space:]]+)?Stamp:[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+' || true)"
[[ -n "$stamp_line" ]] || exit 0
read -r s_branch s_sha s_tree _ <<< "${stamp_line#*Stamp:}"

current="$(stamp_value 5 2>/dev/null)" || exit 0
read -r c_branch _ c_tree <<< "$current"

if [[ "$c_branch" != "$s_branch" ]]; then
  echo "Stale State: branch is $c_branch, State was synced on $s_branch; check State against the repo before trusting Task and Next."
elif [[ "$c_tree" != "$s_tree" ]]; then
  echo "Stale State: code outside kis/ changed since the last sync ($s_sha on $s_branch); check State against the repo before trusting Task and Next."
fi
exit 0
