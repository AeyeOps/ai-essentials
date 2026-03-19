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
Update CHANGELOG.md for version [${new_version}] dated ${today}.

Determine what changed by examining git history since CHANGELOG.md was last modified in a commit. Read the existing CHANGELOG.md and follow its style exactly.

Output only the new section starting with \`## [${new_version}]\` — nothing else.

Exclude: local file paths, environment-specific details, developer names, PII, secrets, references to unrelated projects.
PROMPT

section=$(env -u CLAUDECODE claude -p "$prompt")

# Extract the ## [ section in case of preamble
section=$(printf '%s\n' "$section" | sed -n '/^## \[/,$p')

if [[ -z "$section" ]]; then
  echo "FAIL: claude -p returned no changelog section" >&2
  exit 1
fi

# Ensure trailing newline
[[ "$section" == *$'\n' ]] || section="${section}"$'\n'

# Insert before first existing ## [ line
tmpfile=$(mktemp)
insert_line=$(grep -n '^## \[' CHANGELOG.md | head -1 | cut -d: -f1)
if [[ -n "$insert_line" ]]; then
  head -n $((insert_line - 1)) CHANGELOG.md > "$tmpfile"
  printf '%s\n' "$section" >> "$tmpfile"
  tail -n +$insert_line CHANGELOG.md >> "$tmpfile"
else
  cat CHANGELOG.md > "$tmpfile"
  printf '\n%s\n' "$section" >> "$tmpfile"
fi
mv "$tmpfile" CHANGELOG.md

entry_count=$(grep -c '^- ' <<< "$section" || true)
echo "  generated ${entry_count} entries"

# --- 3. Stage, commit, CI ---
echo "[3/3] Staging, committing, and running CI..."
git add -A
git commit -m "Bump version to ${new_version}"
make ci
