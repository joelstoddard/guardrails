#!/usr/bin/env bash
# A small app with a users table and numbered SQL migrations, so a schema change is plainly migration work.
set -euo pipefail
git init -q -b main
git config user.name "Eval User"
git config user.email "eval@example.com"
git config commit.gpgsign false
mkdir -p db/migrations
cat > db/migrations/001_create_users.sql <<'EOF'
CREATE TABLE users (
  id BIGSERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
EOF
cat > README.md <<'EOF'
# widgets

Postgres 16. Migrations in db/migrations run in filename order at deploy time.
EOF
git add .
git commit -q -m "Add users table"
