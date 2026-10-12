#!/usr/bin/env bash
# Fails unless a release tag `ios-X.Y.Z` names the version the build will actually carry.
#
#   bash ci/check-release-tag.sh ios-0.6.1
#
# Without an argument it reads the tag from the CI environment: CM_TAG on Codemagic,
# GITHUB_REF_NAME on a GitHub tag push. The version comes from MARKETING_VERSION in
# project.yml, which is what CFBundleShortVersionString resolves to.
#
# Used by .github/workflows/release-testflight.yml before it asks Codemagic for a build, and
# by the first step of ios-testflight in codemagic.yaml, so a tag pushed on the wrong commit
# (or a version bump that never got its tag) stops in seconds instead of after a signed build
# that App Store Connect then files under the wrong version.
#
# A Codemagic build started by hand on a branch has no tag. That is allowed, with a warning,
# unless REQUIRE_RELEASE_TAG=1.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
spec="${PROJECT_SPEC:-$root/project.yml}"

tag="${1:-${CM_TAG:-}}"
if [ -z "$tag" ] && [ "${GITHUB_REF_TYPE:-}" = "tag" ]; then
  tag="${GITHUB_REF_NAME:-}"
fi

if [ ! -f "$spec" ]; then
  echo "error: $spec not found" >&2
  exit 1
fi

# First `MARKETING_VERSION: "X.Y.Z"` in the spec (settings.base). Quotes optional.
version="$(sed -n -E 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"?([^"[:space:]#]+)"?.*$/\1/p' "$spec" | head -n 1)"
if [ -z "$version" ]; then
  echo "error: could not read MARKETING_VERSION from $spec" >&2
  exit 1
fi

if [ -z "$tag" ]; then
  if [ "${REQUIRE_RELEASE_TAG:-0}" = "1" ]; then
    echo "error: no release tag given (pass ios-$version, or set CM_TAG / GITHUB_REF_NAME)" >&2
    exit 1
  fi
  echo "warning: no release tag; building MARKETING_VERSION $version from a branch" >&2
  exit 0
fi

case "$tag" in
  ios-*) tag_version="${tag#ios-}" ;;
  *)
    echo "error: release tags look like ios-X.Y.Z; got '$tag'" >&2
    exit 1
    ;;
esac

if ! printf '%s\n' "$tag_version" | grep -Eq '^[0-9]+\.[0-9]+(\.[0-9]+)?$'; then
  echo "error: '$tag' is not ios-X.Y.Z" >&2
  exit 1
fi

if [ "$tag_version" != "$version" ]; then
  cat >&2 <<EOF
error: tag $tag does not match MARKETING_VERSION $version in project.yml.

The build would be uploaded as $version, not $tag_version. Either:
  - bump MARKETING_VERSION to $tag_version, commit, and tag that commit, or
  - delete the tag and tag the commit that carries $tag_version:
      git tag -d $tag && git push origin :refs/tags/$tag
EOF
  exit 1
fi

echo "ok: $tag matches MARKETING_VERSION $version"
