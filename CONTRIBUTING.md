# Contributing to herdr-orch

Thanks for helping. herdr-orch is one skill file and a watcher script, so the bar is: every
change keeps it short, matches what Herdr actually does, and is checked.

## Getting set up

```bash
git clone https://github.com/smkamranqadri/herdr-orch.git && cd herdr-orch
tests/run.sh
```

The installer suite runs in a temporary HOME and never touches your real `~/.agents` or
`~/.claude`. With Herdr installed, `tests/test-skill.sh` also checks every `herdr` command the
skill names against your Herdr.

## What a good pull request looks like

- **One change, with its check.** A fix to the installer comes with a test that fails without it.
  A change to the orch's behaviour updates the matching scenario in `evals/evals.json`.
- **Guards are mutation-checked.** If you add a check, break it on purpose, confirm its test
  fails, and restore it. Mention it in the PR.
- **Only real Herdr commands.** Check each new command or flag with `herdr <command> --help`.
- **Keep `SKILL.md` short.** Agents load all of it on every use.
- **Bump `metadata.version`** in `skills/herdr-orch/SKILL.md` and add a line to `CHANGELOG.md`
  for any change that ships.

## Where things live

```text
skills/herdr-orch/     what installs into ~/.agents/skills/herdr-orch
  SKILL.md             what the orch reads when the skill is invoked
  agents/openai.yaml   Codex metadata
evals/                 scenarios and the sandbox builder
tests/                 one suite per area, run by tests/run.sh
docs/assets/           README images
```

## Running the evals

`evals/setup.sh <new-dir> <1|2|3> [--with-skill skills/herdr-orch]` builds a fictional sandbox
repo for one scenario. Start an orch in a Herdr tab inside it, give it the scenario's prompt,
and score its transcript against `expected_behavior`. Run each scenario with and without the
skill to see what the skill changes.

## Reporting bugs

Open an issue with your OS, your Herdr, Claude Code or Codex versions, what you asked the orch,
what it did, and the relevant lines of its transcript. Please remove anything private first.
