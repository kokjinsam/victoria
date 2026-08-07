#!/bin/sh
set -eu

repository=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
smoke_root=$(mktemp -d "${TMPDIR:-/tmp}/victoria-generated-consumer.XXXXXX")
package="$smoke_root/package"
consumer="$smoke_root/consumer"

cleanup() {
  rm -rf -- "$smoke_root"
}
trap cleanup EXIT HUP INT TERM

version=$(apalache-mc version | tr -d '[:space:]')
case "$version" in
  0.58.3|v0.58.3) ;;
  *) printf 'expected Apalache 0.58.3, got %s\n' "$version" >&2; exit 1 ;;
esac

cd "$repository"
mix hex.build --unpack --output "$package"
mkdir "$consumer"
cp -R test/consumers/generated/. "$consumer/"
cp "$repository/.tool-versions" "$consumer/.tool-versions"

cd "$consumer"
VICTORIA_PACKAGE_PATH="$package" mix deps.get
VICTORIA_PACKAGE_PATH="$package" mix compile --warnings-as-errors
VICTORIA_PACKAGE_PATH="$package" mix test
