#!/bin/sh
set -eu

repository=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
smoke_root=$(mktemp -d "${TMPDIR:-/tmp}/victoria-fixed-consumer.XXXXXX")
package="$smoke_root/package"
consumer="$smoke_root/consumer"

cd "$repository"
mix hex.build --unpack --output "$package"
mkdir "$consumer"
cp -R test/consumers/fixed/. "$consumer/"

cd "$consumer"
VICTORIA_PACKAGE_PATH="$package" mix deps.get
VICTORIA_PACKAGE_PATH="$package" mix compile --warnings-as-errors
VICTORIA_PACKAGE_PATH="$package" mix test
