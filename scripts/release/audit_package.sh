#!/bin/sh
set -eu

repository=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
audit_root=$(mktemp -d "${TMPDIR:-/tmp}/victoria-package-audit.XXXXXX")
package="$audit_root/package"

cleanup() {
  rm -rf -- "$audit_root"
}
trap cleanup EXIT HUP INT TERM

cd "$repository"
mix hex.build --unpack --output "$package"

allowed_entries='.formatter.exs
CHANGELOG.md
CONTEXT.md
LICENSE
README.md
hex_metadata.config
mix.exs
lib/'

if find "$package" -type l -print | grep -q .; then
  printf '%s\n' 'package contains a symbolic link' >&2
  exit 1
fi

actual_entries=$(cd "$package" && find . -mindepth 1 -maxdepth 1 -print | \
  sed 's|^./||; /^lib$/s|$|/|' | LC_ALL=C sort)
expected_entries=$(printf '%s\n' "$allowed_entries" | LC_ALL=C sort)

if [ "$actual_entries" != "$expected_entries" ]; then
  printf '%s\n' 'package top-level allowlist mismatch' >&2
  diff -u "$(printf '%s\n' "$expected_entries" > "$audit_root/expected"; printf '%s' "$audit_root/expected")" \
    "$(printf '%s\n' "$actual_entries" > "$audit_root/actual"; printf '%s' "$audit_root/actual")" >&2 || true
  exit 1
fi

if find "$package/lib" ! -type d ! -type f -print | grep -q .; then
  printf '%s\n' 'package lib contains an entry that is not a regular file or directory' >&2
  exit 1
fi

if find "$package" \( -name test -o -name tmp -o -name _build -o -name deps -o -name doc -o -name .cover \
  -o -name .elixir_ls -o -name .github -o -name .git \) -print | grep -q .; then
  printf '%s\n' 'package contains a forbidden path' >&2
  exit 1
fi

if find "$package" -type f \( -name '*.itf.json' -o -name 'apalachex-run.json' -o -name 'victoria-run.json' \
  -o -name 'apalache-mc' \
  -o -name '*.smt2' -o -name '*.sqlite' -o -name '*.beam' \) -print | grep -q .; then
  printf '%s\n' 'package contains a generated or executable artifact' >&2
  exit 1
fi

if LC_ALL=C grep -R -I -n -E '(/Users/|/home/|[A-Za-z]:\\\\Users\\\\)' "$package"; then
  printf '%s\n' 'package contains a local absolute development path' >&2
  exit 1
fi

printf '%s\n' 'package audit passed'
