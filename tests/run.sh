#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rc=0
for t in "$DIR"/test_*.sh; do echo "== $t"; bash "$t" || rc=1; done
# The Python suites need the PyYAML pinned in requirements.txt. uv supplies it without a project environment;
# CI installs the same file with pip.
if command -v uv >/dev/null; then py=(uv run --quiet --no-project --with-requirements "$DIR/requirements.txt" python3); else py=(python3); fi
echo "== python"; "${py[@]}" -m unittest discover -s "$DIR" -p 'test_*.py' || rc=1
exit $rc
