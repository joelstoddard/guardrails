#!/usr/bin/env bash
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/helper.sh"
. "$DIR/../lib/repo-cmd.sh"

# Repo whose AGENTS.md documents test + lint as labelled inline-code lines
r="$(make_repo main)"
cat > "$r/AGENTS.md" <<'EOF'
# AGENTS.md — sample
## Commands
- **Test:** `make test`
- **Lint:** `ruff check .`
EOF
assert_eq "$(repo_cmd "$r" test)" "make test" "test cmd extracted"
assert_eq "$(repo_cmd "$r" lint)" "ruff check ." "lint cmd extracted"

# Repo with no AGENTS.md → non-zero, empty output
r2="$(make_repo main)"
repo_cmd "$r2" test; RC=$?; assert_rc 1 "missing AGENTS.md → rc1"

finish "repo-cmd"
