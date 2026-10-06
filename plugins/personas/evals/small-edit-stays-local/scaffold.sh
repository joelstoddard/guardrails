#!/usr/bin/env bash
# A README with one typo: a change too small for any persona.
set -euo pipefail
git init -q -b main
git config user.name "Eval User"
git config user.email "eval@example.com"
git config commit.gpgsign false
cat > README.md <<'EOF'
# widgets

Run `./greet.sh NAME` to recieve a greeting.
EOF
git add README.md
git commit -q -m "Add README"
