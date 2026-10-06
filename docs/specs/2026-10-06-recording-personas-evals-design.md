# Plugin evals: suites for recording and personas

Extends `docs/specs/2026-10-05-plugin-evals-design.md`. Every decision there holds here:
Haiku 4.5 pinned, a $2 ceiling per suite run, local runs only, threshold 1.0, free graders,
both arms, and the runner `tests/evals.sh <plugin>`. So do its notes on reading a run and
on running on macOS.

## Why these cases

Each case checks one promise the plugin makes, with a scored grader the no-plugin arm should
fail. Indicators (`arm: with-only`, and `tool_used: Skill`, which the tool excludes itself)
show whether a skill body or only the rules did the work.

## recording

| Case | Promise | Scored | Indicator |
| --- | --- | --- | --- |
| `adr-writes-design-doc` | A decision is recorded as `docs/design/<concept>.md` | `file_exists docs/design/*.md` | `adr` fired |
| `track-findings-footer` | An issue body ends with the Claude Code footer; issues are never commented on, edited or closed | The footer in an assistant line of the trace; no `gh issue comment\|close\|edit\|reopen` | `track-findings` fired |
| `findings-listed-with-refs` | An out-of-scope finding is listed under "Findings outside scope" and ends with a reference | That heading in the reply; the `/tmp/greet.log` item ends with `#N`, an issue URL, `(asked)` or `(declined)` | none |

- **The footer grader reads assistant lines only.** The skill's own text, which contains the
  footer, arrives in a user line, so loading the skill cannot pass the grader by itself.
  It covers both paths the skill allows: a `gh issue create` command, or a draft shown
  when filing needs the user's go-ahead.
- **No case can reach GitHub.** As in `publish-refused`, the run has no network, and the
  remotes name an owner longer than GitHub's 39-character login limit.
- **`findings-listed-with-refs` puts the finding in the file Claude must edit.** `greet.sh`
  appends to a fixed `/tmp/greet.log` path, so the out-of-scope problem is in plain sight,
  not left to chance.

## personas

| Case | Promise | Scored |
| --- | --- | --- |
| `migration-routes-to-data-engineer` | Substantial domain work reaches the matching persona | The trace dispatches `"subagent_type":"personas:data-engineer"` |
| `small-edit-stays-local` | A small edit stays with the main session | No dispatch of any `personas:` agent |

- **Routing is graded on the dispatch's `subagent_type`, not on a tool name.** Traces name
  the dispatch tool `Task`, while the docs call it `Agent`.
- **Eval never loads a plugin's dependencies, and skips a plugin whose dependencies are
  missing.** personas declares `building` and `recording`. In a run, Claude Code skipped it
  without any warning, both from the working tree and from the installed copy: the runs
  listed no personas agents and ran none of its hooks. A case cannot add the dependencies
  through `plugins:`, because the eval refuses entries outside the case's own plugin. A
  copy with only the `dependencies` field removed loaded and routed, which proves the cause.
  So `tests/evals.sh` runs any plugin that declares dependencies from such a copy, with
  `--trust-plugin` for that copy and results written back to the plugin's own
  `evals/results/`. The rules of `building` and `recording` are absent in these runs either
  way.
- **`small-edit-stays-local` should pass in both arms.** It guards against over-delegation,
  so a `Δ` near zero is the expected result, not a weak case.
- **Personas inherit the session's model,** so the persona in the migration case also runs
  on Haiku.

## First runs

One `--runs 1` pass per suite on Haiku 4.5, 2026-10-06, with no run errors:

| Case | With | W/out | Δ | What happened |
| --- | --- | --- | --- | --- |
| `adr-writes-design-doc` | 1.00 | 0.00 | +1.00 | `adr` fired and wrote `docs/design/` |
| `track-findings-footer` | 0.50 | 0.50 | 0.00 | `track-findings` did not fire; Claude ran `gh issue create` bare (#97) |
| `findings-listed-with-refs` | 0.00 | 0.00 | 0.00 | Claude fixed the bug and never mentioned the `/tmp` log |
| `migration-routes-to-data-engineer` | 1.00 | 0.00 | +1.00 | Claude dispatched `personas:data-engineer` |
| `small-edit-stays-local` | 1.00 | 1.00 | 0.00 | All seven personas loaded, and none was dispatched |

The personas rows are from the run through the no-dependencies copy. The first personas
run, before that, loaded no personas at all.

## Verification

`tests/test_eval_graders.py` pins every new grader against examples built in the trace's
real shape, including the `flags` a grader sets, and checks each scaffold builds the state
its prompt relies on. Mutating the footer anchor or the routing pattern fails it.
