# guardrails

Three Claude Code plugins in one marketplace: `building`, `recording` and `personas`. See `README.md`.

## Commands

- **Test:** `bash tests/run.sh`
- **Lint:** `bash tests/lint.sh`

The suite needs bash 4.1 or newer (stock macOS bash is 3.2), `jq`, the `claude` CLI (for `claude plugin validate`), and Python 3 with PyYAML. With `uv` installed, the runner supplies PyYAML itself.

Lint needs `shellcheck` and `actionlint`. It fails on any shellcheck warning or error in a shell script, and on any actionlint finding in the workflows.
