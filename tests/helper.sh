#!/usr/bin/env bash
# Minimal test helper for hook scripts and libs. No external deps beyond git+jq.
FAILS=0

# run_hook <script-path> <json-on-stdin>  → sets OUT, ERR, RC
run_hook() {
  local script="$1" json="$2" errfile
  errfile="$(mktemp)"
  OUT="$(printf '%s' "$json" | bash "$script" 2>"$errfile")"; RC=$?
  ERR="$(cat "$errfile")"; rm -f "$errfile"
}

# make_repo <default-branch>  → prints path to a fresh temp git repo on that branch
make_repo() {
  local d; d="$(mktemp -d)"
  git -C "$d" init -q -b "$1"
  git -C "$d" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -q --allow-empty -m init
  printf '%s\n' "$d"
}

assert_rc()  { [ "$RC" = "$1" ] || { echo "  FAIL [$2]: rc=$RC expected $1 (err: $ERR)"; FAILS=1; }; }
assert_err() { case "$ERR" in *"$1"*) ;; *) echo "  FAIL [$2]: stderr missing '$1' (got: $ERR)"; FAILS=1;; esac; }
assert_out() { case "$OUT" in *"$1"*) ;; *) echo "  FAIL [$2]: stdout missing '$1' (got: $OUT)"; FAILS=1;; esac; }
assert_eq()  { [ "$1" = "$2" ] || { echo "  FAIL [$3]: '$1' != '$2'"; FAILS=1; }; }
finish()     { [ "$FAILS" = 0 ] && echo "OK: $1" || { echo "FAILED: $1"; exit 1; }; }
