#!/usr/bin/env bash
# Minimal test helper for hook scripts and libs. No external deps beyond git+jq.
FAILS=0

# Tests make commits, and a user's commit.gpgsign would make each one wait on a GPG prompt.
# The environment form ranks with -c, above every config file.
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false

# Tests make temp paths with scratch_dir and scratch_file, under one dir removed when the test exits.
# A test's own EXIT trap would replace this one, so tests set none.
_HELPER_TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$_HELPER_TMP"' EXIT
scratch_dir()  { mktemp -d "$_HELPER_TMP/d.XXXXXX"; }
scratch_file() { mktemp "$_HELPER_TMP/f.XXXXXX"; }

# run_hook <script-path> <json-on-stdin>  → sets OUT, ERR, RC
run_hook() {
  local script="$1" json="$2" errfile
  errfile="$(scratch_file)"
  OUT="$(printf '%s' "$json" | bash "$script" 2>"$errfile")"; RC=$?
  ERR="$(cat "$errfile")"; rm -f "$errfile"
}

# make_repo <default-branch>  → prints path to a fresh temp git repo on that branch
make_repo() {
  local d; d="$(scratch_dir)"
  git -C "$d" init -q -b "$1"
  git -C "$d" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -q --allow-empty -m init
  printf '%s\n' "$d"
}

assert_rc()  { [ "$RC" = "$1" ] || { echo "  FAIL [$2]: rc=$RC expected $1 (err: $ERR)"; FAILS=1; }; }
assert_err() { case "$ERR" in *"$1"*) ;; *) echo "  FAIL [$2]: stderr missing '$1' (got: $ERR)"; FAILS=1;; esac; }
assert_out() { case "$OUT" in *"$1"*) ;; *) echo "  FAIL [$2]: stdout missing '$1' (got: $OUT)"; FAILS=1;; esac; }
assert_eq()  { [ "$1" = "$2" ] || { echo "  FAIL [$3]: '$1' != '$2'"; FAILS=1; }; }
finish()     { if [ "$FAILS" = 0 ]; then echo "OK: $1"; else echo "FAILED: $1"; exit 1; fi; }
