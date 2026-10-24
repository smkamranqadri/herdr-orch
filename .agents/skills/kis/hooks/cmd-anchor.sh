#!/usr/bin/env bash
# Command Code SessionStart adapter: runs session-anchor.sh and wraps its text in the JSON shape cmd
# expects from a hook (plain stdout is ignored). Usage: cmd-anchor.sh [project-root]; the SessionStart
# payload arrives on stdin and its "cwd" is the fallback root. Any failure prints {} and exits 0, so
# it can never break a session start.
set -uo pipefail

hooks_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v ruby >/dev/null 2>&1 || { echo '{}'; exit 0; }

# -E UTF-8:UTF-8 keeps a State with an em dash from failing in a C or unset locale.
ruby -E UTF-8:UTF-8 -rjson -e '
  hooks_dir, root_arg = ARGV
  begin
    payload = {}
    begin
      parsed = JSON.parse($stdin.read.to_s.scrub)
      payload = parsed if parsed.is_a?(Hash)
    rescue JSON::ParserError
    end

    root = root_arg.to_s.strip
    root = payload["cwd"].to_s.strip if root.empty?
    root = Dir.pwd if root.empty?

    anchor = File.join(hooks_dir, "session-anchor.sh")
    unless File.executable?(anchor)
      puts "{}"
      exit 0
    end
    text = IO.popen([anchor, root], err: File::NULL, &:read).to_s.scrub
    if !$?.success? || text.strip.empty?
      puts "{}"
    else
      puts JSON.generate({ "hookSpecificOutput" => { "hookEventName" => "SessionStart", "additionalContext" => text } })
    end
  rescue StandardError
    puts "{}"
  end
' "$hooks_dir" "${1:-}" || echo '{}'
exit 0
