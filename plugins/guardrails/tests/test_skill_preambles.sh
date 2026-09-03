#!/usr/bin/env bash
# Skill preamble commands run before the skill does anything. A worktree-isolated
# session refuses any command whose arguments come from command substitution, because
# it cannot statically verify the command stays inside the worktree — and step 1 of the
# documented workflow mandates a worktree. So a preamble using $() aborts the skill in
# the exact situation it was written for. Pipes and || are fine; only $() is refused.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/helper.sh"
SKILLS="$DIR/../skills"

# Checks the whole file, not just preamble lines: an instruction in the prose telling an
# agent to run a command is refused exactly the same way a preamble command is. The
# first pass of this test only scanned preamble lines and missed eight such sites.
for f in "$SKILLS"/*/SKILL.md; do
  name="$(basename "$(dirname "$f")")"
  n=0
  while IFS= read -r line; do
    n=$((n + 1))
    case "$line" in
      *'$('*)
        where="prose"
        case "$line" in *'!`'*) where="preamble" ;; esac
        echo "  FAIL [$name:$n]: $where uses command substitution — refused in a worktree"
        echo "         $(printf '%s' "$line" | cut -c1-90)"
        FAILS=1 ;;
    esac
  done < "$f"
done

finish "skill-preambles"
