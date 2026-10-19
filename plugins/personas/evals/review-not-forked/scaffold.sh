#!/usr/bin/env bash
# A one-line script, so the main session implements the change itself and the review is the only dispatch.
set -euo pipefail
git init -q -b main
git config user.name "Eval User"
git config user.email "eval@example.com"
git config commit.gpgsign false
cat > greet.sh <<'EOF'
#!/usr/bin/env bash
echo "Hello, ${1:-world}"
EOF
git add greet.sh
git commit -q -m "Add greet.sh"
