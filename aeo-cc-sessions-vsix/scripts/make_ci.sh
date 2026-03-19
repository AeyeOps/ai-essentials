#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "=== CI: Build & Validate ==="
make package

VERSION="$(node -p "require('./package.json').version")"
TAG="v${VERSION}"
BRANCH="$(git branch --show-current)"
HEAD_SHA="$(git rev-parse HEAD)"
echo ""
echo "=== CI: Version check — ${TAG} ==="

LOCAL_TAG_SHA=""
if git rev-parse -q --verify "${TAG}^{commit}" >/dev/null 2>&1; then
  LOCAL_TAG_SHA="$(git rev-parse "${TAG}^{commit}")"
fi

REMOTE_TAG_SHA="$(git ls-remote --tags origin "${TAG}^{}" | awk '{print $1}')"

if [[ -n "$REMOTE_TAG_SHA" ]]; then
  if [[ "$REMOTE_TAG_SHA" == "$HEAD_SHA" ]]; then
    echo "Remote tag ${TAG} already points at HEAD — version already released."
    exit 0
  fi

  echo "FAIL: Remote tag ${TAG} already exists on a different commit (${REMOTE_TAG_SHA})." >&2
  echo "Current HEAD is ${HEAD_SHA}." >&2
  exit 1
fi

if [[ -n "$LOCAL_TAG_SHA" && "$LOCAL_TAG_SHA" != "$HEAD_SHA" ]]; then
  echo "FAIL: Local tag ${TAG} points at ${LOCAL_TAG_SHA}, not HEAD ${HEAD_SHA}." >&2
  exit 1
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
echo "=== CI: Pushing branch ==="
git push origin "$BRANCH"

echo ""
echo "=== CI: Tagging & pushing ==="
if [[ -z "$LOCAL_TAG_SHA" ]]; then
  git tag -a "$TAG" -m "Release ${TAG}"
else
  echo "Local tag ${TAG} already exists on HEAD — reusing it."
fi
git push origin "$TAG"

echo ""
echo "Pushed ${BRANCH}, tagged ${TAG}, and pushed the tag — GitHub Actions release workflow triggered."
