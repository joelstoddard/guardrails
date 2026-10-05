# guardrails

Claude Code plugins that keep an agent honest while it builds, record what it decides
and finds, and let it delegate to specialists.

| Plugin | What it does |
|---|---|
| `building` | Blocks publishing as the user and commits on the default branch, gates tests on push, warns on lint, suppressions and long comments, and drives commit, rebase, stacked diffs, draft PRs, CI watching and pre-PR checks |
| `recording` | Keeps findings tracked, nudges pending lessons, and drives ADRs, RFCs, mistake write-ups, project memory and self-improvement |
| `personas` | Seven specialist subagents (architect, data-engineer, qa-engineer, release-engineer, sre, security-engineer, technical-writer) and their delegation rules. Installs `building` and `recording` too |

Each plugin injects its standing rules at session and subagent start.

## Install

```bash
claude plugin marketplace add joelstoddard/guardrails
claude plugin install building@guardrails
claude plugin install recording@guardrails
claude plugin install personas@guardrails
```

Or declare it in `~/.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "guardrails": { "source": { "source": "github", "repo": "joelstoddard/guardrails" }, "autoUpdate": true }
  },
  "enabledPlugins": {
    "building@guardrails": true,
    "recording@guardrails": true,
    "personas@guardrails": true
  }
}
```

The plugins carry no `version`, so with `autoUpdate` every push to `main` arrives at the
next session.

Prerequisites: `jq`, and the `superpowers` plugin from `claude-plugins-official`
(`recording:rfc` and `recording:self-improvement` use its brainstorming and worktree skills).

## Develop

```bash
claude --plugin-dir ./plugins   # loads all three from this checkout, replacing installed copies
bash tests/run.sh               # needs bash 4.1+, jq, the claude CLI, and Python 3 with PyYAML (or uv)
bash tests/lint.sh              # needs shellcheck and actionlint
bash tests/evals.sh building --runs 1   # behaviour evals: real model usage, run locally by hand
```
