#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  install-anchor.sh [--target <project-root>] [--settings <path>] [--hooks-json <path>]
                    [--codex-hooks <path>] [--cmd-settings <path>]
                    [--instructions <path>]... [--no-hook] [--no-instructions]
                    [--check] [--remove]

Installs the KIS re-anchor layer into a project:
  - a Claude SessionStart hook that injects current State at session start, resume, clear, and compact
  - an Antigravity PreInvocation hook that injects current State at the first model call of every turn
  - a Codex SessionStart hook (project scope, .codex/hooks.json); Codex skips it until you trust it
    once with /hooks
  - a Command Code SessionStart hook (project scope, .commandcode/settings.json)
  - a marked KIS block in the project instruction files that every host loads automatically

Options:
  --target <path>        Project root. Defaults to current directory.
  --settings <path>      Claude settings file. Defaults to <target>/.claude/settings.json.
  --hooks-json <path>    Antigravity hooks file. Defaults to <target>/.agents/hooks.json.
  --codex-hooks <path>   Codex hooks file. Defaults to <target>/.codex/hooks.json.
  --cmd-settings <path>  Command Code settings file. Defaults to <target>/.commandcode/settings.json.
  --instructions <path>  Instruction file to carry the KIS block. Repeatable.
                         Defaults to AGENTS.md, plus CLAUDE.md when it already exists.
  --no-hook              Skip all four session hooks.
  --no-instructions      Skip the instruction file block.
  --check                Report what is installed and change nothing.
  --remove               Remove the hook entries and the instruction block.
  -h, --help             Show this help.
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

target_root="."
settings_file=""
hooks_json_file=""
codex_hooks_file=""
cmd_settings_file=""
instruction_files=()
want_hook="true"
want_instructions="true"
mode="apply"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      [[ $# -ge 2 ]] || die "--target requires a path"
      target_root="$2"
      shift 2
      ;;
    --settings)
      [[ $# -ge 2 ]] || die "--settings requires a path"
      settings_file="$2"
      shift 2
      ;;
    --hooks-json)
      [[ $# -ge 2 ]] || die "--hooks-json requires a path"
      hooks_json_file="$2"
      shift 2
      ;;
    --codex-hooks)
      [[ $# -ge 2 ]] || die "--codex-hooks requires a path"
      codex_hooks_file="$2"
      shift 2
      ;;
    --cmd-settings)
      [[ $# -ge 2 ]] || die "--cmd-settings requires a path"
      cmd_settings_file="$2"
      shift 2
      ;;
    --instructions)
      [[ $# -ge 2 ]] || die "--instructions requires a path"
      instruction_files+=("$2")
      shift 2
      ;;
    --no-hook)
      want_hook="false"
      shift
      ;;
    --no-instructions)
      want_instructions="false"
      shift
      ;;
    --check)
      mode="check"
      shift
      ;;
    --remove)
      mode="remove"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

command -v ruby >/dev/null 2>&1 || die "ruby is required to edit settings and instruction files"

target_root="$(mkdir -p "$target_root" && cd "$target_root" && pwd -P)"
[[ -n "$settings_file" ]] || settings_file="$target_root/.claude/settings.json"
[[ -n "$hooks_json_file" ]] || hooks_json_file="$target_root/.agents/hooks.json"
[[ -n "$codex_hooks_file" ]] || codex_hooks_file="$target_root/.codex/hooks.json"
[[ -n "$cmd_settings_file" ]] || cmd_settings_file="$target_root/.commandcode/settings.json"

if [[ ${#instruction_files[@]} -eq 0 ]]; then
  instruction_files=("$target_root/AGENTS.md")
  if [[ -f "$target_root/CLAUDE.md" ]]; then
    instruction_files+=("$target_root/CLAUDE.md")
  fi
fi

# Every ruby call below runs with -E UTF-8:UTF-8: without a locale (CI, a devcontainer) ruby reads a
# file as US-ASCII and a hook file or instruction file with an accented letter would abort.
# Shared by every JSON merge below: a missing or empty file is {}, and anything the hosts would not
# parse (comments, trailing commas, a non-object) aborts before any file is written.
ruby_json_lib='
def load_json(path)
  return {} unless File.file?(path)
  raw = File.read(path).strip
  return {} if raw.empty?
  begin
    data = JSON.parse(raw)
  rescue JSON::ParserError => e
    abort("cannot parse #{path}: #{e.message}")
  end
  # Ruby json accepts // and /* */ comments but the hosts parse strictly: refuse the file instead of
  # rewriting it with the comments quietly dropped. String literals are blanked out first.
  if raw.gsub(/"(?:\\.|[^"\\])*"/m, "\"\"").match?(%r{//|/\*})
    abort("cannot parse #{path}: comments are not valid JSON")
  end
  abort("#{path} is not a JSON object") unless data.is_a?(Hash)
  data
end

# The pre-KIS copy of a file, kept once: written only while the file has no KIS entry yet, and never
# over the backup of a file that carries one, so it stays what the user had before KIS touched it. A
# file with no KIS entry is the user'"'"'s current copy, so a backup left by an earlier install is
# replaced by it, or moved aside when the file does not exist, rather than kept as a stale copy.
def backup_original(path, had_kis_entry)
  return if had_kis_entry
  bak = path + ".kis-bak"
  if File.file?(path)
    FileUtils.rm_f(bak)  # a symlink left at the backup name must not be written through
    FileUtils.cp(path, bak)
  elsif File.exist?(bak)
    # The user removed the file themselves: keep the backup under another name, it may be their only copy.
    FileUtils.mv(bak, "#{bak}.#{Time.now.strftime("%Y%m%d%H%M%S")}#{rand(1000)}")
  end
end

# A successful remove hands the file back as the user'"'"'s own, so its pre-install copy has done its job.
# Keeping it would make a later install-then-remove treat a file KIS created as one the user had.
def drop_backup(path)
  FileUtils.rm_f(path + ".kis-bak")
end
'

hook_command='"$CLAUDE_PROJECT_DIR"/.agents/skills/kis/hooks/session-anchor.sh'
hook_marker='kis/hooks/session-anchor.sh'

antigravity_hook_name="kis-anchor"
# Compared as absolute paths (File.absolute_path: a leading ~ is a directory name, not a home) so ".agents/hooks.json" and the absolute spelling pick the same command.
if [[ "$(ruby -e 'puts File.absolute_path(ARGV[0])' "$hooks_json_file")" == "$(ruby -e 'puts File.absolute_path(ARGV[0])' "$target_root/.agents/hooks.json")" ]]; then
  # Antigravity runs a hook command from the directory holding hooks.json.
  antigravity_hook_command="./skills/kis/hooks/antigravity-anchor.sh"
else
  antigravity_hook_command="$target_root/.agents/skills/kis/hooks/antigravity-anchor.sh"
fi

# Codex and Command Code run the hook from the session directory, which may be below the project
# root, and the project may sit below the git root (a monorepo) or have no git at all. The command
# walks up from the session directory to the nearest one holding the package, runs it there, and
# stays silent when none does (also when the session directory is unknown or relative, where the walk
# would never end). POSIX sh, no git. Codex takes the anchor's plain stdout; cmd needs its JSON
# adapter. The hook timeout is 20 s: the stamp check inside the anchor is capped at 5 s, so a slow
# stamp costs its line and not the anchor.
hook_timeout=20
codex_hook_command='d=$PWD; case $d in /*) ;; *) exit 0;; esac; while :; do h="$d/.agents/skills/kis/hooks/session-anchor.sh"; [ -x "$h" ] && exec "$h" "$d"; [ "$d" = / ] && exit 0; d=$(dirname "$d"); done'
codex_hook_marker='kis/hooks/session-anchor.sh'
cmd_hook_command='d=$PWD; case $d in /*) ;; *) exit 0;; esac; while :; do h="$d/.agents/skills/kis/hooks/cmd-anchor.sh"; [ -x "$h" ] && exec "$h" "$d"; [ "$d" = / ] && exit 0; d=$(dirname "$d"); done'
cmd_hook_marker='kis/hooks/cmd-anchor.sh'
# Commands earlier releases of KIS shipped, one per line. A re-install refreshes an entry carrying one
# of these (or the current command with the old stock timeout of 10) and leaves any other command that
# holds the marker alone: that one is the user's.
codex_prev_commands='root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"; h="$root/.agents/skills/kis/hooks/session-anchor.sh"; [ -x "$h" ] && exec "$h" "$root"; exit 0
d=$PWD; while :; do h="$d/.agents/skills/kis/hooks/session-anchor.sh"; [ -x "$h" ] && exec "$h" "$d"; [ "$d" = / ] && exit 0; d=$(dirname "$d"); done'
cmd_prev_commands='root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"; h="$root/.agents/skills/kis/hooks/cmd-anchor.sh"; [ -x "$h" ] && exec "$h" "$root"; exit 0
d=$PWD; while :; do h="$d/.agents/skills/kis/hooks/cmd-anchor.sh"; [ -x "$h" ] && exec "$h" "$d"; [ "$d" = / ] && exit 0; d=$(dirname "$d"); done'

apply_hook() {
  ruby -E UTF-8:UTF-8 -rjson -rfileutils -e "$ruby_json_lib"'
    settings_path, hook_command, hook_marker, mode = ARGV
    data = load_json(settings_path)
    exit 0 if mode == "validate"

    hooks = data["hooks"] ||= {}
    events = hooks["SessionStart"] ||= []
    installed = events.any? do |entry|
      Array(entry["hooks"]).any? { |h| h["command"].to_s.include?(hook_marker) }
    end

    case mode
    when "check"
      puts(installed ? "Claude SessionStart hook: installed" : "Claude SessionStart hook: missing")
      exit 0
    when "remove"
      unless installed
        puts "Claude SessionStart hook: nothing to remove"
        exit 0
      end
      # Keys the user had before KIS are put back empty rather than dropped; the pre-install copy says
      # which those were.
      had_hooks = had_session_start = false
      begin
        original = JSON.parse(File.read(settings_path + ".kis-bak"))
        if original.is_a?(Hash) && original["hooks"].is_a?(Hash)
          had_hooks = true
          had_session_start = original["hooks"]["SessionStart"].is_a?(Array)
        end
      rescue SystemCallError, JSON::ParserError
      end
      events.each do |entry|
        entry["hooks"] = Array(entry["hooks"]).reject { |h| h["command"].to_s.include?(hook_marker) }
      end
      events.reject! { |entry| Array(entry["hooks"]).empty? }
      hooks.delete("SessionStart") if events.empty? && !had_session_start
      data.delete("hooks") if hooks.empty? && !had_hooks
      # A file KIS created (no pre-install backup) that holds nothing else goes away with its entry.
      if data.empty? && !File.exist?(settings_path + ".kis-bak")
        File.delete(settings_path) if File.file?(settings_path)
        puts "Claude SessionStart hook: removed #{settings_path}"
        exit 0
      end
      puts "Claude SessionStart hook: removed from #{settings_path}"
    else
      if installed
        puts "Claude SessionStart hook: already installed"
        exit 0
      end
      events << {
        "matcher" => "startup|resume|clear|compact",
        "hooks" => [{ "type" => "command", "command" => hook_command }]
      }
      puts "Claude SessionStart hook: added to #{settings_path}"
    end

    FileUtils.mkdir_p(File.dirname(settings_path))
    backup_original(settings_path, installed)
    File.write(settings_path, JSON.pretty_generate(data) + "\n")
    drop_backup(settings_path) if mode == "remove"
  ' "$settings_file" "$hook_command" "$hook_marker" "$mode"
}

apply_antigravity_hook() {
  ruby -E UTF-8:UTF-8 -rjson -rfileutils -e "$ruby_json_lib"'
    hooks_path, hook_name, hook_command, mode = ARGV
    data = load_json(hooks_path)
    exit 0 if mode == "validate"

    installed = data.key?(hook_name)
    # The entry is stock when it is what KIS ships: one PreInvocation command hook with timeout 15 whose
    # command is the relative one, or one absolute path to the package that is the current command or names
    # a file that is gone (a moved project). A wrapper, or a live path to another package, is the user'"'"'s.
    # A stock entry that differs from the current command is refreshed; anything else under the KIS name is the user'"'"'s and is left alone, as for Codex and
    # Command Code.
    stock = { "PreInvocation" => [{ "type" => "command", "command" => hook_command, "timeout" => 15 }] }
    entry = data[hook_name]
    pre = entry.is_a?(Hash) && entry.keys == ["PreInvocation"] && entry["PreInvocation"].is_a?(Array) ? entry["PreInvocation"] : []
    h = pre.size == 1 && pre[0].is_a?(Hash) ? pre[0] : {}
    command = h["command"].to_s
    stock_like = h.keys.sort == %w[command timeout type] && h["type"] == "command" && h["timeout"] == 15 &&
      (command == "./skills/kis/hooks/antigravity-anchor.sh" ||
       (command.match?(%r{\A/\S+/\.agents/skills/kis/hooks/antigravity-anchor\.sh\z}) && (command == hook_command || !File.exist?(command))))
    custom = installed && !stock_like
    outdated = installed && stock_like && entry != stock

    case mode
    when "check"
      puts(!installed ? "Antigravity PreInvocation hook: missing" : custom ? "Antigravity PreInvocation hook: installed, customised, left alone" : outdated ? "Antigravity PreInvocation hook: installed, but its command is outdated (re-run install-anchor.sh to refresh it)" : "Antigravity PreInvocation hook: installed")
      exit 0
    when "remove"
      unless installed
        puts "Antigravity PreInvocation hook: nothing to remove"
        exit 0
      end
      data.delete(hook_name)
      if data.empty? && File.file?(hooks_path) && !File.exist?(hooks_path + ".kis-bak")
        File.delete(hooks_path)
        puts "Antigravity PreInvocation hook: removed #{hooks_path}"
        exit 0
      end
      puts "Antigravity PreInvocation hook: removed from #{hooks_path}"
    else
      if installed && !outdated
        puts "Antigravity PreInvocation hook: #{custom ? "customised, left alone" : "already installed"}"
        exit 0
      end
      data[hook_name] = stock
      puts "Antigravity PreInvocation hook: #{installed ? "refreshed in" : "added to"} #{hooks_path}"
    end

    FileUtils.mkdir_p(File.dirname(hooks_path))
    backup_original(hooks_path, installed)
    File.write(hooks_path, JSON.pretty_generate(data) + "\n")
    drop_backup(hooks_path) if mode == "remove"
  ' "$hooks_json_file" "$antigravity_hook_name" "$antigravity_hook_command" "$mode"
}

# One SessionStart hook in a {"hooks": {"SessionStart": [{"hooks": [...]}]}} file, the shape Codex and
# Command Code share. Other hooks and keys in the file are left alone. An existing file is copied once
# to <file>.kis-bak before KIS first edits it (the pre-install copy, never overwritten). An entry that
# is a command KIS shipped earlier, or the current command with the old timeout of 10, is refreshed in
# place (its timeout is kept unless it was that 10); any other command containing the marker is the
# user's and is reported "customised, left alone". A trust note, when given, is printed after a real
# add or refresh, since Codex keys its trust on the command.
apply_session_start_hook() {  # <label> <file> <marker> <command> <trust note>
  ruby -E UTF-8:UTF-8 -rjson -rfileutils -e "$ruby_json_lib"'
    label, path, marker, command, trust_note, prev_commands, stock_timeout, mode = ARGV
    prev = prev_commands.split("\n")
    stock_timeout = stock_timeout.to_i
    data = load_json(path)

    hooks = data["hooks"]
    abort("#{path}: \"hooks\" is not an object") unless hooks.nil? || hooks.is_a?(Hash)
    hooks ||= {}
    events = hooks["SessionStart"]
    abort("#{path}: \"hooks.SessionStart\" is not a list") unless events.nil? || events.is_a?(Array)
    events ||= []
    exit 0 if mode == "validate"

    kis_hooks = events.flat_map do |entry|
      entry.is_a?(Hash) ? Array(entry["hooks"]).select { |h| h.is_a?(Hash) && h["command"].to_s.include?(marker) } : []
    end
    installed = !kis_hooks.empty?
    # stale: shipped by an earlier KIS (or stock command, old timeout); custom: anything else with the marker.
    stale = kis_hooks.select { |h| prev.include?(h["command"]) || (h["command"] == command && h["timeout"] == 10) }
    custom = kis_hooks.reject { |h| h["command"] == command || prev.include?(h["command"]) }

    case mode
    when "check"
      notes = []
      unless stale.empty?
        timeout_only = stale.all? { |h| h["command"] == command }
        notes << "but its #{timeout_only ? "timeout" : "command"} is outdated (re-run install-anchor.sh to refresh it)"
      end
      notes << "customised, left alone" unless custom.empty?
      state = !installed ? "missing" : notes.empty? ? "installed" : "installed, #{notes.join("; ")}"
      puts "#{label} SessionStart hook: #{state}"
      exit 0
    when "remove"
      unless installed
        puts "#{label} SessionStart hook: nothing to remove"
        exit 0
      end
      # Keys the user had before KIS are put back empty rather than dropped; the pre-install copy
      # says which those were.
      had_hooks = had_session_start = false
      begin
        original = JSON.parse(File.read(path + ".kis-bak"))
        if original.is_a?(Hash) && original["hooks"].is_a?(Hash)
          had_hooks = true
          had_session_start = original["hooks"]["SessionStart"].is_a?(Array)
        end
      rescue SystemCallError, JSON::ParserError
      end
      events.each do |entry|
        next unless entry.is_a?(Hash)
        entry["hooks"] = Array(entry["hooks"]).reject { |h| h.is_a?(Hash) && h["command"].to_s.include?(marker) }
      end
      events.reject! { |entry| entry.is_a?(Hash) && entry.key?("hooks") && Array(entry["hooks"]).empty? }
      if events.empty? && !had_session_start then hooks.delete("SessionStart") else hooks["SessionStart"] = events end
      if hooks.empty? && !had_hooks then data.delete("hooks") else data["hooks"] = hooks end
      puts "#{label} SessionStart hook: removed from #{path}"
    else
      if installed && stale.empty?
        puts "#{label} SessionStart hook: #{custom.empty? ? "already installed" : "customised, left alone"}"
        exit 0
      end
      if installed
        stale.each do |h|
          h["command"] = command
          h["timeout"] = stock_timeout if h["timeout"] == 10
        end
        puts "#{label} SessionStart hook: refreshed in #{path}"
        puts "#{label} SessionStart hook: customised entry left alone" unless custom.empty?
      else
        events << { "hooks" => [{ "type" => "command", "command" => command, "timeout" => stock_timeout }] }
        puts "#{label} SessionStart hook: added to #{path}"
      end
      hooks["SessionStart"] = events
      data["hooks"] = hooks
      puts trust_note unless trust_note.empty?
    end

    FileUtils.mkdir_p(File.dirname(path))
    backup_original(path, installed)
    # A file KIS created (no pre-install copy) that holds nothing else goes away with its entry; one the
    # user had before KIS stays, as the {} it was reduced to.
    if data.empty? && mode == "remove" && !File.exist?(path + ".kis-bak")
      File.delete(path) if File.file?(path)
    else
      File.write(path, JSON.pretty_generate(data) + "\n")
    end
    drop_backup(path) if mode == "remove"
  ' "$1" "$2" "$3" "$4" "$5" "$6" "$hook_timeout" "$mode"
}

codex_trust_note="Codex: run /hooks once and trust the KIS SessionStart hook. Codex skips new hooks until you do, and project hooks load only when the project's .codex/ layer is trusted."

apply_instructions() {
  local file
  for file in "${instruction_files[@]}"; do
    ruby -E UTF-8:UTF-8 -e '
      path, mode = ARGV
      start_marker = "<!-- kis:anchor:start -->"
      end_marker = "<!-- kis:anchor:end -->"

      block = <<~BLOCK.strip
        #{start_marker}
        ## KIS Project Memory

        This project uses KIS memory under `kis/`. Knowledge = stable facts. Intent = goals and plans. State = current reality.

        - Read `kis/state/` before planning or implementing, then only the Intent and Knowledge the task needs.
        - Put each fact in exactly one layer, and update an existing file instead of creating a new one.
        - Prove work with real command or verification output before marking anything done.
        - Synchronize the KIS layers that changed when work finishes.
        - Full instructions: `.agents/skills/kis/SKILL.md`.
        - Commands live in `.agents/skills/kis/commands/`: start, plan, act, sync, check, init.
          Claude `/kis:start`, Pi and OpenCode `/kis-start`, Codex `/prompts:kis-start`.
          Antigravity has no custom slash commands: name the step and follow its command file.
        #{end_marker}
      BLOCK

      exists = File.file?(path)
      text = exists ? File.read(path) : ""
      pattern = /#{Regexp.escape(start_marker)}.*?#{Regexp.escape(end_marker)}\n?/m
      present = text.match?(pattern)

      case mode
      when "check"
        puts "#{path}: #{present ? "KIS block present" : "KIS block missing"}"
        exit 0
      when "remove"
        unless present
          puts "#{path}: no KIS block to remove"
          exit 0
        end
        File.write(path, text.sub(pattern, "").gsub(/\n{3,}/, "\n\n").lstrip)
        puts "#{path}: KIS block removed"
      else
        if present
          File.write(path, text.sub(pattern, block + "\n"))
          puts "#{path}: KIS block refreshed"
        else
          separator = text.empty? || text.end_with?("\n\n") ? "" : (text.end_with?("\n") ? "\n" : "\n\n")
          File.write(path, text + separator + block + "\n")
          puts "#{path}: KIS block added"
        end
      end
    ' "$file" "$mode"
  done
}

if [[ "$want_hook" == "true" ]]; then
  # Parse all four files before writing any of them, so a file the hosts would reject aborts the run
  # with nothing changed.
  if [[ "$mode" != "check" ]]; then
    real_mode="$mode"; mode="validate"
    apply_hook
    apply_antigravity_hook
    apply_session_start_hook "Codex" "$codex_hooks_file" "$codex_hook_marker" "$codex_hook_command" "$codex_trust_note" "$codex_prev_commands"
    apply_session_start_hook "Command Code" "$cmd_settings_file" "$cmd_hook_marker" "$cmd_hook_command" "" "$cmd_prev_commands"
    mode="$real_mode"
  fi
  apply_hook
  apply_antigravity_hook
  apply_session_start_hook "Codex" "$codex_hooks_file" "$codex_hook_marker" "$codex_hook_command" "$codex_trust_note" "$codex_prev_commands"
  apply_session_start_hook "Command Code" "$cmd_settings_file" "$cmd_hook_marker" "$cmd_hook_command" "" "$cmd_prev_commands"
fi

if [[ "$want_instructions" == "true" ]]; then
  apply_instructions
fi
