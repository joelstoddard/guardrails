#!/usr/bin/env bash
# The hook reports and never deletes, so every case asserts two things: the
# worktree still exists, and the report says the right thing about it. The
# ignored-file case is the regression test for the bug that shipped deletion —
# `git status --porcelain` cannot see ignored files and `git worktree remove`
# does not refuse them, so a merged worktree full of plans was deletable.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/helper.sh"
HOOK="$DIR/../hooks/scripts/post-merge-cleanup.sh"

refute_out() { case "$OUT" in *"$1"*) echo "  FAIL [$2]: stdout should not contain '$1' (got: $OUT)"; FAILS=1;; esac; }
assert_dir() { [ -d "$1" ] || { echo "  FAIL [$2]: $1 no longer exists"; FAILS=1; }; }

# Build a repo with an origin, a default branch, and a worktree per scenario.
setup() {
  root="$(mktemp -d)"
  git init --quiet --bare "$root/origin.git"
  git init --quiet -b main "$root/repo"
  git -C "$root/repo" config user.email t@t; git -C "$root/repo" config user.name t
  git -C "$root/repo" remote add origin "$root/origin.git"
  mkdir -p "$root/repo/.claude/worktrees"
  echo base > "$root/repo/f"; git -C "$root/repo" add f
  git -C "$root/repo" commit --quiet -m base
  git -C "$root/repo" push --quiet -u origin main
  git -C "$root/repo" remote set-head origin main
}

# Create a worktree on a new branch. $2=merged, $3=dirty, $4=has an ignored file.
mkwt() {
  name="$1"; merged="$2"; dirty="$3"; ignored="$4"
  wt="$root/repo/.claude/worktrees/$name"
  git -C "$root/repo" worktree add --quiet -b "$name" "$wt" >/dev/null 2>&1 \
    || { echo "  FAIL [fixture]: worktree add failed for $name"; FAILS=1; return 1; }
  echo "$name" > "$wt/$name"
  git -C "$wt" add "$name"
  if [ "$ignored" = yes ]; then echo 'scratch/' > "$wt/.gitignore"; git -C "$wt" add .gitignore; fi
  git -C "$wt" commit --quiet -m "$name"
  if [ "$merged" = yes ]; then
    git -C "$root/repo" push --quiet origin "$name:main"
    git -C "$root/repo" fetch --quiet origin
  fi
  # Written after the commit so the tree is clean under plain --porcelain and
  # only --ignored sees it: exactly the state the old hook silently deleted.
  if [ "$ignored" = yes ]; then mkdir -p "$wt/scratch"; echo plan > "$wt/scratch/plan.md"; fi
  if [ "$dirty" = yes ]; then echo scratch > "$wt/dirty"; fi
  return 0
}

run() { OUT="$(printf '{"cwd":"%s"}' "$1" | bash "$HOOK" 2>/dev/null)"; }

# --- merged + clean is reported, not removed
setup; mkwt merged-clean yes no no
run "$root/repo"
assert_dir "$root/repo/.claude/worktrees/merged-clean" "merged clean"
# the paths git prints are symlink-resolved, so match the tail, not $root
assert_out "merged-clean — git worktree remove /" "merged clean"
assert_out "/.claude/worktrees/merged-clean" "merged clean"
refute_out "WARNING" "merged clean"

# --- merged with only an IGNORED file: kept, and the report warns
setup; mkwt merged-ignored yes no yes
run "$root/repo"
assert_dir "$root/repo/.claude/worktrees/merged-ignored" "ignored-file worktree"
[ -f "$root/repo/.claude/worktrees/merged-ignored/scratch/plan.md" ] \
  || { echo "  FAIL [ignored-file worktree]: the ignored file was deleted"; FAILS=1; }
assert_out "merged-ignored — WARNING: holds uncommitted or ignored files, inspect before: git worktree remove" "ignored-file worktree"

# --- merged + dirty: kept, and the report warns
setup; mkwt merged-dirty yes yes no
run "$root/repo"
assert_dir "$root/repo/.claude/worktrees/merged-dirty" "merged dirty"
assert_out "merged-dirty — WARNING: holds uncommitted or ignored files, inspect before: git worktree remove" "merged dirty"

# --- unmerged is not reported at all
setup; mkwt unmerged no no no
run "$root/repo"
assert_dir "$root/repo/.claude/worktrees/unmerged" "unmerged"
refute_out "unmerged" "unmerged"

# --- the session's own worktree is not reported
setup; mkwt self-wt yes no no
run "$root/repo/.claude/worktrees/self-wt"
assert_dir "$root/repo/.claude/worktrees/self-wt" "self worktree"
refute_out "self-wt" "self worktree"

# --- a worktree outside .claude/worktrees/ is ignored
setup
git -C "$root/repo" worktree add --quiet -b outside "$root/outside" >/dev/null 2>&1 \
  || { echo "  FAIL [fixture]: worktree add failed for outside"; FAILS=1; }
git -C "$root/repo" push --quiet origin outside:main; git -C "$root/repo" fetch --quiet origin
run "$root/repo"
assert_dir "$root/outside" "outside the convention"
refute_out "outside" "outside the convention"

# --- a diverged default branch is not rewritten
setup
# give origin a commit local will not have
echo remote > "$root/repo/remote-side"; git -C "$root/repo" add remote-side
git -C "$root/repo" commit --quiet -m remote-side
git -C "$root/repo" push --quiet origin main
git -C "$root/repo" reset --hard --quiet HEAD~1
# and give local a different commit origin does not have
echo local > "$root/repo/local-side"; git -C "$root/repo" add local-side
git -C "$root/repo" commit --quiet -m local-side
git -C "$root/repo" fetch --quiet origin
before="$(git -C "$root/repo" rev-parse HEAD)"
run "$root/repo"
[ "$(git -C "$root/repo" rev-parse HEAD)" = "$before" ] \
  || { echo "  FAIL: rewrote a diverged default branch"; FAILS=1; }

# --- a repo that does not use the convention is left entirely alone
setup
rm -rf "$root/repo/.claude"
# advance origin ahead of local; without the guard the hook would fast-forward onto it
git -C "$root/repo" checkout --quiet -b ahead-tmp
echo ahead > "$root/repo/ahead"; git -C "$root/repo" add ahead
git -C "$root/repo" commit --quiet -m ahead
git -C "$root/repo" push --quiet origin ahead-tmp:main
git -C "$root/repo" checkout --quiet main
git -C "$root/repo" fetch --quiet origin
before="$(git -C "$root/repo" rev-parse HEAD)"
run "$root/repo"
[ "$(git -C "$root/repo" rev-parse HEAD)" = "$before" ] \
  || { echo "  FAIL: acted on a repo not using the .claude/worktrees convention"; FAILS=1; }

# --- fail-open: no origin, and a plain directory
setup
git -C "$root/repo" remote remove origin
run "$root/repo" || { echo "  FAIL: nonzero exit with no origin"; FAILS=1; }
run "$(mktemp -d)" || { echo "  FAIL: nonzero exit outside a git repo"; FAILS=1; }

finish "post-merge-cleanup"
