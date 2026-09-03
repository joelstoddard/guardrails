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

# A label line that runs on into prose is a description, not a command. Real
# case: netboxlabs/netbox-changes documents its CI job under "- **tests**:" and
# mentions NetBox's `main` branch before naming the command it runs. Taking the
# first code span yields `main`, which is not a program, so the gate "fails" and
# blocks every push.
r3="$(make_repo main)"
cat > "$r3/AGENTS.md" <<'EOF'
# AGENTS.md — sample
## CI
  - **tests**: Matrix across Python 3.12/3.13. Checks out NetBox `main` (or a `test-against:<ref>` label), runs `manage.py test app.tests --keepdb`.
EOF
assert_eq "$(repo_cmd "$r3" test)" "" "prose description yields no command"
repo_cmd "$r3" test; RC=$?; assert_rc 1 "prose description -> rc1"

# Same, but wrapped so the label line ends with a code span. Guards against a
# fix that only counts spans or checks the line's last one.
r4="$(make_repo main)"
cat > "$r4/AGENTS.md" <<'EOF'
# AGENTS.md — sample
## CI
  - **tests**: Matrix across Python 3.12/3.13. Checks out NetBox `main`
    (or a ref from a label), then runs `manage.py test app.tests --keepdb`.
EOF
assert_eq "$(repo_cmd "$r4" test)" "" "wrapped prose yields no command"

# Positive regressions: the documented shapes must still extract.
r5="$(make_repo main)"
cat > "$r5/AGENTS.md" <<'EOF'
# AGENTS.md — sample
Test = `go test ./...`
* **Lints**: `golangci-lint run`
EOF
assert_eq "$(repo_cmd "$r5" test)" "go test ./..." "equals separator still extracts"
assert_eq "$(repo_cmd "$r5" lint)" "golangci-lint run" "plural label still extracts"

finish "repo-cmd"
