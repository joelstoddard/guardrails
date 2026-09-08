#!/usr/bin/env bash
# Report worktrees whose branch is already merged, then fast-forward the default
# branch. Runs at session start in every repo on this machine, so every failure
# path exits 0 and nothing is ever deleted — reporting only.
# See docs/specs/2026-09-07-guardrails-autonomy-design.md
command -v jq >/dev/null 2>&1 || exit 0
input="$(cat)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[ -n "$cwd" ] || cwd="$PWD"

# The session may be sitting in a worktree; act on the repo that owns it.
common="$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || exit 0
[ -n "$common" ] || exit 0
main_wt="$(dirname "$common")"
[ -d "$main_wt/.claude/worktrees" ] || exit 0

self_wt="$(git -C "$cwd" rev-parse --path-format=absolute --show-toplevel 2>/dev/null)"

# GIT_TERMINAL_PROMPT=0 so a credential prompt fails fast instead of hanging
# session start on a repo whose remote needs auth.
GIT_TERMINAL_PROMPT=0 git -C "$main_wt" fetch --prune --quiet origin 2>/dev/null

def="$(git -C "$main_wt" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
if [ -z "$def" ]; then
  for b in main master develop; do
    git -C "$main_wt" show-ref --verify --quiet "refs/heads/$b" && { def="$b"; break; }
  done
fi
[ -n "$def" ] || exit 0
base="refs/remotes/origin/$def"
git -C "$main_wt" show-ref --verify --quiet "$base" || base="refs/heads/$def"

# --ff-only means a diverged local branch is left alone rather than rewritten.
cur="$(git -C "$main_wt" symbolic-ref --quiet --short HEAD 2>/dev/null)"
if [ "$cur" = "$def" ] && [ -z "$(git -C "$main_wt" status --porcelain 2>/dev/null)" ]; then
  git -C "$main_wt" merge --ff-only --quiet "$base" 2>/dev/null
fi

# Known limitation: merge-base --is-ancestor only sees true merges, so a branch
# that was squash- or rebase-merged is not reported. Under-reporting is the safe
# direction for a report — the worktree simply stays until the user removes it.
report=""
_report_one() {
  [ -n "$path" ] && [ -n "$branch" ] || return 0
  case "$path" in "$main_wt"/.claude/worktrees/*) ;; *) return 0 ;; esac
  [ "$path" != "$self_wt" ] || return 0
  git -C "$main_wt" merge-base --is-ancestor "refs/heads/$branch" "$base" 2>/dev/null || return 0
  # --ignored as well as --porcelain: plans, notes and build output are ignored,
  # not untracked, and `git worktree remove` deletes them without complaint.
  if [ -n "$(git -C "$path" status --porcelain --ignored 2>/dev/null)" ]; then
    report="$report
  $branch — WARNING: holds uncommitted or ignored files, inspect before: git worktree remove $path"
  else
    report="$report
  $branch — git worktree remove $path"
  fi
}

path=""; branch=""
while IFS= read -r line; do
  case "$line" in
    "worktree "*) path="${line#worktree }" ;;
    "branch "*)   branch="${line#branch refs/heads/}" ;;
    "")           _report_one; path=""; branch="" ;;
  esac
done <<EOF
$(git -C "$main_wt" worktree list --porcelain 2>/dev/null)
EOF
_report_one   # the final record has no trailing blank line

[ -n "$report" ] && echo "Merged worktrees, not removed:$report"
exit 0
