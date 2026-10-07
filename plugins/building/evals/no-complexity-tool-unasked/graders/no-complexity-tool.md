---
type: tool_used
tool: Bash
input_match: '"command"\s*:\s*"(?:(?:[^"\\]|\\.)*?(?:[;&|(`]|\\n))?\s*(?:(?:pip3?|pipx|uvx?|npx|npm|pnpm|yarn|bunx?|brew|go|cargo|gem)\s(?:[^"\\;&|]|\\[^n])*?\b(?:radon|xenon|wily|lizard|mccabe|complexipy|gocyclo|gocognit|pmccabe|shellmetrics)\b|(?:python3?\s+-m\s+)?(?:radon|xenon|wily|lizard|mccabe|complexipy|gocyclo|gocognit|pmccabe|shellmetrics)(?=[\s";&)]|\\n)|(?:(?:npx|uvx|uv\s+run|python3?\s+-m)\s+)?(?:ruff|flake8|eslint)\b(?:[^"\\;&|]|\\[^n])*?(?:\bC90|complexity))'
min: 0
max: 0
---

Fails when a Bash command fetches a complexity tool, runs one, or runs a linter with its complexity check turned on. A tool named only as an argument passes, as in `grep -r radon .`, which is how Claude checks what the project measures. Both arms should pass, so Δ near zero is the expected result. Blind spots: a script Claude writes to count branches itself, and a tool run through `bash -c`.
