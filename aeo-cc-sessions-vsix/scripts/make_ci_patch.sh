#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# --- 1. Bump patch version ---
echo "[1/3] Bumping patch version..."
old_version=$(node -p "require('./package.json').version")
npm version patch --no-git-tag-version --silent
new_version=$(node -p "require('./package.json').version")
echo "  ${old_version} -> ${new_version}"

# --- 2. Generate changelog entry ---
echo "[2/3] Generating CHANGELOG.md entry..."
today=$(date -u +%Y-%m-%d)

read -r -d '' prompt <<PROMPT || true
Add a new section to CHANGELOG.md for version [${new_version}] dated ${today}.

Examine git history since the last time CHANGELOG.md was modified in a commit to determine what changed. Insert the new section directly into the file, following the existing style.

Exclude: local file paths, environment-specific details, developer names, PII, secrets, references to unrelated projects.
PROMPT

env -u CLAUDECODE claude -p "$prompt"

# Verify the entry landed
if ! grep -q "^## \[${new_version}\]" CHANGELOG.md; then
  echo "FAIL: CHANGELOG.md does not contain a [${new_version}] section" >&2
  exit 1
fi

entry_count=$(sed -n "/^## \[${new_version}\]/,/^## \[/p" CHANGELOG.md | grep -c '^- ' || true)
echo "  ${entry_count} entries"

# --- 3. Stage, commit, CI ---
echo "[3/3] Staging, committing, and running CI..."
git add -A
git commit -m "Bump version to ${new_version}"
make ci
