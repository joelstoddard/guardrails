#!/usr/bin/env bash
# Run one plugin's eval suite with pinned settings, so scores compare across runs.
# Each run is a real model call, so run it locally by hand; see docs/specs/2026-10-05-plugin-evals-design.md
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL=claude-haiku-4-5-20251001
plugin="${1:?usage: bash tests/evals.sh <plugin> [claude plugin eval options...]}"
shift
target="$ROOT/plugins/$plugin"
extra=()
# Eval skips a plugin whose declared dependencies are not loaded, and it cannot load them.
# So such a plugin runs from a copy without the field; see docs/specs/2026-10-06-recording-personas-evals-design.md
if jq -e 'has("dependencies")' "$target/.claude-plugin/plugin.json" >/dev/null; then
  copy="$(mktemp -d)"
  trap 'rm -rf "$copy"' EXIT
  cp -R "$target/." "$copy/"
  jq 'del(.dependencies)' "$target/.claude-plugin/plugin.json" > "$copy/.claude-plugin/plugin.json"
  # The copy is this checkout's own plugin, so trusting it is the trust already given to the checkout.
  extra=(--trust-plugin --output-dir "$target/evals/results/$(date -u +%Y-%m-%dT%H-%M-%SZ)")
  target="$copy"
fi
# The run's sandbox cannot read a git under your home or run the macOS /usr/bin/git shim.
# So the run inherits a PATH that starts at the resolved git's own directory; see the first spec above.
git_bin="$(command -v git)"
git_dir="$(dirname "$(realpath "$git_bin")")"
export PATH="$git_dir:$PATH"
# The target goes first, because --allow-tools takes a list and reads any later argument as a tool.
claude plugin eval "$target" \
  --model "$MODEL" --judge-model "$MODEL" \
  --threshold 1 --max-cost-usd 2 \
  --allow-tools Bash --scaffold --no-publish ${extra[@]+"${extra[@]}"} "$@"
