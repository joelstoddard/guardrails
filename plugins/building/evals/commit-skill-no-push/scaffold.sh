#!/usr/bin/env bash
# A feature branch with an uncommitted bugfix, so the case asks for a commit but never a push.
# The seed subject is deliberately not conventional, so the no-plugin arm has no style to copy from git log.
set -euo pipefail
git init -q -b main
git config user.name "Eval User"
git config user.email "eval@example.com"
git config commit.gpgsign false
cat > greet.sh <<'EOF'
#!/usr/bin/env bash
echo "Hello, $1"
EOF
git add greet.sh
git commit -q -m "Add greeting script"
git switch -q -c fix/empty-input
cat > greet.sh <<'EOF'
#!/usr/bin/env bash
echo "Hello, ${1:-world}"
EOF
