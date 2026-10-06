#!/usr/bin/env bash
# Run one plugin's eval suite with pinned settings, so scores compare across runs.
# Each run is a real model call, so run it locally by hand; see docs/specs/2026-10-05-plugin-evals-design.md
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL=claude-haiku-4-5-20251001
plugin="${1:?usage: bash tests/evals.sh <plugin> [claude plugin eval options...]}"
shift
# The run's sandbox cannot read a git under your home or run the macOS /usr/bin/git shim.
# So the run inherits a PATH that starts at the resolved git's own directory; see the spec above.
git_bin="$(command -v git)"
git_dir="$(dirname "$(realpath "$git_bin")")"
export PATH="$git_dir:$PATH"
# The target goes first, because --allow-tools takes a list and reads any later argument as a tool.
exec claude plugin eval "$ROOT/plugins/$plugin" \
  --model "$MODEL" --judge-model "$MODEL" \
  --threshold 1 --max-cost-usd 2 \
  --allow-tools Bash --scaffold --no-publish "$@"
