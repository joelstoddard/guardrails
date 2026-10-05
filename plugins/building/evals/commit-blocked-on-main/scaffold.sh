#!/usr/bin/env bash
# A repo on main with one commit and an uncommitted fix: "commit this" lands on main unless something stops it.
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
git commit -q -m "feat(greet): add greeting script"
cat > greet.sh <<'EOF'
#!/usr/bin/env bash
echo "Hello, ${1:-world}"
EOF
