# Commands And Re-Anchoring

Commands are explicit entry points into the KIS loop. The re-anchor layer keeps KIS present when nobody types a command.

## Command Files

`commands/` holds host-neutral bodies, one per loop step, each with `description` and `argument-hint` frontmatter that Claude, Pi, and Codex all read.

| File | Step |
| --- | --- |
| `start.md` | LOAD: recover context, report current reality, propose a work mode. |
| `init.md` | Bootstrap `kis/` for a project that has none. |
| `plan.md` | QUESTION, CHALLENGE, STRUCTURE, PLAN: interview, then produce an approved scope. |
| `act.md` | ACT: execute the current task with proof. |
| `sync.md` | SYNCHRONIZE: write what changed into the right layer. |
| `check.md` | Maintenance: audit for contradictions, staleness, and bloat. |

Keep each command pointed at one step. A command that restates the whole skill becomes a second source of truth.

## Host Adapters

Install with `scripts/install-commands.sh --host project|claude|pi|opencode|codex|all`. The default is `project`, which covers Claude and Pi and writes nothing outside the project.

| Host | Adapter | Invocation |
| --- | --- | --- |
| Claude | `.claude/commands/kis` symlinked to `commands/` | `/kis:start` |
| Pi | `.pi/prompts/kis-*.md` symlinked per file, since Pi's prompt discovery is not recursive | `/kis-start` |
| OpenCode | `.opencode/command/kis-*.md` symlinked per file, since OpenCode command names come from the filename | `/kis-start` |
| Codex | `${CODEX_HOME:-~/.codex}/prompts/kis-*.md` copies | `/prompts:kis-start` |
| Antigravity | none: it supports rules, skills, plugins, hooks, and MCP, but not custom slash commands | name the step, or point it at the command file |

Claude, Pi, and OpenCode links follow package updates. Codex prompts are user-level, cannot be shared through a repository, and are copies, so re-run the installer after an update. OpenAI marks Codex custom prompts deprecated in favor of skills, so treat them as a convenience layer over the skill.

Pi, OpenCode, and Antigravity discover the skill itself from `.agents/skills/`, so no adapter is needed to reach it. Claude does not, which is why the installer also links `.claude/skills/kis`. On any host, the command files are also plain instructions: an agent can be told to follow `.agents/skills/kis/commands/sync.md` directly.

In Claude the skill and the commands are separate entries with the same name. `/kis` runs the skill, which is the whole loop and the path the model takes when it triggers KIS on its own. `/kis:start` and its siblings enter one step. Both are expected; neither replaces the other.

## Re-Anchor Layer

Commands only fire when someone types one. Drift happens when a long session buries the skill and the agent stops loading State, stops interviewing, stops requiring proof, or stops synchronizing.

`scripts/install-anchor.sh` installs the anchor on four hosts plus the instruction block:

- A Claude `SessionStart` hook running `hooks/session-anchor.sh` on startup, resume, clear, and compact. It prints the KIS rules, the command list, and a short State summary: Branch, Run (only when State has a `Run:` line), Task, Blocker and Next, with indented continuation lines joined and the value cut at `KIS_ANCHOR_MAX_FIELD_CHARS` (default 200) bytes, backed off to a character boundary so a multibyte character is never split, and read byte-wise so an invalid byte in a line cannot lose the summary, beside a pointer to the file, all within the `KIS_ANCHOR_MAX_LINES` line budget (default 20, minimum 18). When State carries a `Stamp:` line and the code outside `kis/` or the branch no longer matches it, one `Stale State: ...` line from `scripts/state-stamp.sh --check` (capped at 5 seconds, so a slow check drops the line, not the anchor) follows the State heading. Blocker and Next fall back to the first `## Open` and `## Next` item when their bullet labels are absent, so every session and every post-compaction context starts from current operational reality without re-reading the whole file.
- An Antigravity `PreInvocation` hook in `.agents/hooks.json` running `hooks/antigravity-anchor.sh`, which wraps the same anchor text in an `ephemeralMessage`. The hook fires before every model call and Antigravity drops an ephemeral message after the current turn, so the hook injects at the first invocation of every turn (payload `invocationNum` 0, which Antigravity restarts every turn; a payload without one counts as a first call) and prints `{}` without running the anchor on the other calls. Every turn is anchored with the State as it is then, nothing accumulates in the conversation, and a compaction needs no detection. Antigravity runs lifecycle hooks in an interactive session only, not under `agy --print`.
- A Codex `SessionStart` hook in `.codex/hooks.json` (project scope) running `hooks/session-anchor.sh`, whose plain stdout Codex adds as developer context on startup, resume, clear, compact, and fork. Codex skips a new hook until the user reviews it once with `/hooks`, and loads project hooks only when the project's `.codex/` layer is trusted; the installer prints this step when it adds the hook.
- A Command Code (`cmd`) `SessionStart` hook in `.commandcode/settings.json` (project scope) running `hooks/cmd-anchor.sh`, which wraps the anchor in cmd's `hookSpecificOutput.additionalContext` JSON because cmd ignores plain stdout. cmd fires SessionStart on startup, resume, and clear only, so its anchor is not refreshed by a compaction; cmd records trust for a project hook itself at startup. Limits seen in a live check: print mode (`cmd -p`) runs no SessionStart hooks at all, and a prompt passed at launch is answered before the hook context lands, so the anchor reaches the model from the second turn.
- A marked KIS block in `AGENTS.md` and `CLAUDE.md`, between `<!-- kis:anchor:start -->` and `<!-- kis:anchor:end -->`. Pi, OpenCode, Codex, and Antigravity all load these files automatically.

The Codex and Command Code commands walk up from the session directory to the nearest directory holding `.agents/skills/kis`, so a project below the git root, or one with no git, is found from any subdirectory; they print nothing when the session directory is unknown. Their hook timeout is 20 seconds. All of them are idempotent. `--check` reports each host, `--remove` reverses only the KIS entries, and existing settings, hooks, and instructions are preserved: a hook file that existed before KIS stays, even when empty, and one KIS created goes away with its entry. Re-running the installer refreshes a Codex or Command Code hook only when its command is one an earlier KIS shipped, or the current one with the old timeout of 10, and keeps any other timeout (it prints the Codex trust step again, since Codex trusts a hook by its command). A hook command you changed that still names the KIS script (a Codex, Command Code or Antigravity entry) is reported "customised, left alone" by the installer and by `--check`; a stock Antigravity entry whose command path is outdated (the relative one, or an absolute path to a package that no longer exists, as after moving the project) is refreshed, and a missing one is added. An existing hook file is copied once to `<file>.kis-bak` before KIS first edits it, so the backup is the copy from the last install made while the file had no KIS entry (it is never overwritten while the file carries one, and is moved aside to `<file>.kis-bak.<timestamp>` if you deleted the file yourself); `--remove` deletes it, since the file is the user's again. The installer parses every hook file before writing any, and refuses one with comments or trailing commas, which Codex and Command Code reject too.
