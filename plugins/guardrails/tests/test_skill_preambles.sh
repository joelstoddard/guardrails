#!/usr/bin/env bash
# A worktree-isolated session refuses a command whose arguments come from command
# substitution, so a preamble that uses it aborts the skill it introduces. Pipes
# and || stay permitted.
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/helper.sh"
SKILLS="$DIR/../skills"

# Checks the whole file, not just preamble lines: prose that tells an agent to run a
# command is refused the same way a preamble command is.
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
