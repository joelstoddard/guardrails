#!/usr/bin/env bash
# Fail on any shellcheck warning or error in the repo's shell scripts, and on any actionlint finding
# in the workflows. Needs shellcheck and actionlint on PATH.
set -o pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
rc=0
# Untracked scripts too, so a new one is linted before it is added.
git ls-files -z --cached --others --exclude-standard -- '*.sh' | xargs -0 shellcheck --severity=warning || rc=1
actionlint || rc=1
exit $rc
