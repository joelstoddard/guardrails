#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/helper.sh"

# child <commands> — run commands in a fresh test that sources the helper, so its EXIT trap fires.
child() { bash -c ". \"\$1\"; $1" child "$DIR/helper.sh"; }

repo="$(child 'make_repo main')"
[ -n "$repo" ] || { echo "  FAIL [make_repo prints its repo]"; FAILS=1; }
[ -e "$repo" ] && { echo "  FAIL [make_repo's repo is removed when the test exits]: $repo"; FAILS=1; rm -rf "$repo"; }

made="$(child 'scratch_dir; scratch_file')"
for p in $made; do [ -e "$p" ] && { echo "  FAIL [scratch paths are removed when the test exits]: $p"; FAILS=1; rm -rf "$p"; }; done

# BSD mktemp ignores TMPDIR without a template, so a bare mktemp would land outside the helper's dir.
bare="$(grep -ln "mktemp" "$DIR"/test_*.sh | grep -v "/test_helper.sh$")"
[ -z "$bare" ] || { echo "  FAIL [tests make temp paths with scratch_dir or scratch_file, not mktemp]: $bare"; FAILS=1; }

# A test's own EXIT trap replaces the helper's, so the helper's temp dir would leak.
own="$(grep -l "^[[:space:]]*trap .*EXIT" "$DIR"/test_*.sh)"
[ -z "$own" ] || { echo "  FAIL [tests use cleanup_later, not their own EXIT trap]: $own"; FAILS=1; }

finish "helper"
