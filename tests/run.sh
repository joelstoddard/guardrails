#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rc=0
# Each suite runs under a time limit, so a parser that loops cannot spin on for days (#156). The slowest suite took
# 85 s, and a whole traced run 342 s, on macOS at load 6 to 8; 600 s fails a stuck suite well before CI's job limit.
# The alarm kills the suite's whole process group, so a looping child cannot outlive it. rc 142 is SIGALRM.
within() { # <seconds> <command...>
  perl -e '$t = shift; $p = fork; if (!$p) { setpgrp(0, 0); exec @ARGV or exit 127 }
    $SIG{ALRM} = sub { kill "KILL", -$p; exit 142 }; alarm $t; waitpid($p, 0); exit($? & 127 ? 128 + ($? & 127) : $? >> 8)' "$@"
}
limit="${GUARDRAILS_SUITE_LIMIT:-600}"
for t in "$DIR"/test_*.sh; do
  echo "== $t"; within "$limit" bash "$t"; r=$?
  [ "$r" = 0 ] || { [ "$r" = 142 ] && echo "${t##*/} timed out after $limit s"; rc=1; }
done
# The Python suites need the PyYAML pinned in requirements.txt. uv supplies it without a project environment;
# CI installs the same file with pip.
if command -v uv >/dev/null; then py=(uv run --quiet --no-project --with-requirements "$DIR/requirements.txt" python3); else py=(python3); fi
echo "== python"; "${py[@]}" -m unittest discover -s "$DIR" -p 'test_*.py' || rc=1
exit $rc
