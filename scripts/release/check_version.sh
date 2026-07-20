#!/bin/sh
set -eu

repository=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$repository"

case "${GITHUB_REF:-}" in
  refs/tags/v*) tag_version=${GITHUB_REF#refs/tags/v} ;;
  *)
    printf '%s\n' 'version consistency requires a refs/tags/v* ref' >&2
    exit 1
    ;;
esac

mix_version=$(mix eval --no-compile --no-deps-check --no-archives-check \
  'IO.write(Mix.Project.config()[:version])')

if [ "$tag_version" != "$mix_version" ]; then
  printf 'tag version %s does not match Mix version %s\n' "$tag_version" "$mix_version" >&2
  exit 1
fi

case "$tag_version" in
  *-*) ;;
  *)
    if ! grep -E "^## \[$mix_version\] — [0-9]{4}-[0-9]{2}-[0-9]{2}$" CHANGELOG.md >/dev/null; then
      printf 'stable tag %s requires a dated CHANGELOG.md heading\n' "$tag_version" >&2
      exit 1
    fi
    ;;
esac

printf 'version consistency passed for %s\n' "$mix_version"
