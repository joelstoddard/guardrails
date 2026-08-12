#!/usr/bin/env bash
# Block `git commit` while HEAD is the repo's default branch. Fail-open.
command -v jq >/dev/null 2>&1 || exit 0
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SELF_DIR/../../lib/git-cmd.sh"
input="$(cat)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)"

_guardrails_invokes_git "$cmd" commit || exit 0
[ "${ALLOW_DEFAULT_COMMIT:-}" = "1" ] && exit 0

# Judge the repo git will actually act on, not the one the shell happens to sit in.
# Working one-worktree-per-ticket, the shell sits in the primary checkout (usually on the
# default branch) while the commit is aimed elsewhere — via `cd <worktree> &&` or `-C`.
# Resolving from .cwd alone reads the primary checkout's branch and refuses a commit that
# was never going to land there.
cwd="$(_guardrails_git_effective_cwd "$cmd" commit "${cwd:-.}")"

repo="$(git -C "${cwd:-.}" rev-parse --show-toplevel 2>/dev/null)" || exit 0
cur="$(git -C "$repo" symbolic-ref --quiet --short HEAD 2>/dev/null)" || exit 0

# Resolve default branch: prefer origin/HEAD, else first of main/master/develop that exists.
def="$(git -C "$repo" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
if [ -z "$def" ]; then
  for b in main master develop; do
    git -C "$repo" show-ref --verify --quiet "refs/heads/$b" && { def="$b"; break; }
  done
fi

if [ -n "$def" ] && [ "$cur" = "$def" ]; then
  echo "Refusing to commit on the default branch '$def'. Start a ticket branch (see the start-ticket skill), or set ALLOW_DEFAULT_COMMIT=1 to override." >&2
  exit 2
fi
exit 0
