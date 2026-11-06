# guardrails

Three Claude Code plugins in one marketplace: `building`, `recording` and `personas`. See `README.md`.

## Commands

- **Test:** `bash tests/run.sh`
- **Lint:** `bash tests/lint.sh`
- **Coverage:** `bash tests/coverage.sh`
- **Mutation:** `bash tests/mutate.sh --changed`. Run it before a PR that changes a hook script or `lib/` file.
- **Evals:** `bash tests/evals.sh <plugin> --runs 1`, where `<plugin>` is `building`, `recording` or `personas`. personas runs from a temporary copy without its `dependencies` field, which eval cannot load. Each run is a real model call on your plan, so run them locally, by hand. One run per arm fits the $2 ceiling; the default three can stop partway with exit 2. Add `--case <name>` while iterating. The Bash sandbox refuses to start while `~/.docker` holds symlinks; see `docs/specs/2026-10-05-plugin-evals-design.md`.

The suite needs bash 5 or newer (stock macOS bash is 3.2), gawk, perl, `pgrep` and `pkill`, `jq`, the `claude` CLI (for `claude plugin validate`), and Python 3 with PyYAML. With `uv` installed, the runner supplies PyYAML itself.

Coverage reruns the shell suites under line tracing, so it needs what they need. CI runs the shell suites only this way, once, and the Python tests on their own. It also counts the statements of the awk programs in those files, under gawk, in `awk:` rows. It fails if a hook script, `lib/` file or awk row has no floor in `tests/coverage-floor.tsv`, or falls below it. `bash tests/coverage.sh --update` records a new file's floor and tightens the others, and never loosens one. It measures lines, not branches: there is no branch floor, and the mutation floors stand in for one. See `docs/design/coverage.md`.

Mutation reruns the shell suites under tracing too, then changes one covered line at a time and runs the tests that cover it. It fails if a mutated file's score falls below its floor in `tests/mutation-floor.tsv` with more surviving mutants than the ceiling beside it. Answer each survivor with a test that kills it, or, only if no test could, a row with a reason in `tests/mutants-ignore.tsv`. `bash tests/mutate.sh --update` re-measures every file, about 20 minutes on 14 cores, and never loosens a floor. CI mutates the files a PR changes, and every file weekly.

Lint needs `shellcheck` and `actionlint`. It fails on any shellcheck warning or error in a shell script, and on any actionlint finding in the workflows.
