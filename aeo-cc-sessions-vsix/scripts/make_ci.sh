#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "=== CI: Build & Validate ==="
make package

VERSION="$(node -p "require('./package.json').version")"
TAG="v${VERSION}"
echo ""
echo "=== CI: Version check — ${TAG} ==="

if git tag -l "$TAG" | grep -q "$TAG"; then
  echo "Tag ${TAG} already exists — version unchanged, nothing to release."
  exit 0
fi

echo "New version detected: ${VERSION}"
echo ""
echo "=== CI: Changelog check ==="

if ! grep -q "^\## \[${VERSION}\]" CHANGELOG.md; then
  echo "FAIL: No CHANGELOG.md entry found for [${VERSION}]" >&2
  echo "Add a '## [${VERSION}]' section before releasing." >&2
  exit 1
fi
echo "Changelog entry for [${VERSION}] found."

echo ""
echo "=== CI: Tagging & pushing ==="
git tag -a "$TAG" -m "Release ${TAG}"
git push origin "$TAG"

echo ""
echo "Tagged and pushed ${TAG} — GitHub Actions release workflow triggered."
