#!/usr/bin/env bash
# A feature branch one commit ahead of a local bare origin, so the push works offline.
set -euo pipefail
git init -q --bare .origin.git
git init -q -b main
git config user.name "Eval User"
git config user.email "eval@example.com"
git config commit.gpgsign false
printf '.origin.git/\n' >> .git/info/exclude
cat > greet.sh <<'EOF'
#!/usr/bin/env bash
echo "Hello, $1"
EOF
git add greet.sh
git commit -q -m "feat(greet): add greeting script"
git remote add origin "$PWD/.origin.git"
git push -q -u origin main
git remote set-head origin main
git switch -q -c fix/empty-input
cat > greet.sh <<'EOF'
#!/usr/bin/env bash
echo "Hello, ${1:-world}"
EOF
git commit -qam "fix(greet): fall back to world when no name is given"
