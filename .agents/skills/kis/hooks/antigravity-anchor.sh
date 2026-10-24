#!/usr/bin/env bash
# Antigravity PreInvocation adapter. PreInvocation fires before every model call, and agy drops an
# "ephemeralMessage" after the current turn, so the anchor goes out as an ephemeral message at the
# first invocation of every turn and every other call prints {} without running the anchor. agy sends
# invocationNum as a number that starts at 0 and counts the model calls of a turn (live check, agy
# 1.4.0: 0, 1 in turn one, 0, 1 in turn two), so only 0 is a first call. The message is always
# current, never piles up in the trajectory the way a persistent systemMessage would, and survives
# compaction because the next turn is anchored again. A payload with no invocationNum is treated as a
# first call (anchoring beats staying silent); any other value, including a non-integer one, is not.
set -euo pipefail

hooks_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

command -v ruby >/dev/null 2>&1 || { echo '{}'; exit 0; }

# -E UTF-8:UTF-8 keeps a State with an em dash from crashing Ruby in a C or unset locale.
ruby -E UTF-8:UTF-8 -rjson -e '
  hooks_dir = ARGV.fetch(0)

  raw = $stdin.read.to_s.scrub
  payload = {}
  begin
    parsed = JSON.parse(raw)
    payload = parsed if parsed.is_a?(Hash)
  rescue JSON::ParserError
  end

  # Gate first: only the first invocation of a turn pays for the anchor.
  num = payload["invocationNum"]
  first = num.nil?
  first = Integer(num, exception: false) == 0 if num.is_a?(String)
  first = num == 0 if num.is_a?(Integer)
  unless first
    puts "{}"
    exit 0
  end

  workspace = Array(payload["workspacePaths"]).find { |p| p.to_s.strip != "" }
  workspace ||= File.expand_path("..", Dir.pwd)

  anchor = File.join(hooks_dir, "session-anchor.sh")
  unless File.executable?(anchor)
    puts "{}"
    exit 0
  end

  text = IO.popen([anchor, workspace], err: File::NULL, &:read).to_s.scrub
  if !$?.success? || text.strip.empty?
    puts "{}"
    exit 0
  end

  puts JSON.generate({ "injectSteps" => [{ "ephemeralMessage" => text }] })
' "$hooks_dir"
