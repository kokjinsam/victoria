#!/bin/sh
set -eu

version=0.58.3
archive_name="apalache-$version.tgz"
checksum=ba622db9538aebf942cc7a7815f942a6b2b419012707e16dfdc25a73ff95d0a5
url="https://github.com/apalache-mc/apalache/releases/download/v$version/$archive_name"
install_root=${1:?usage: install_apalache.sh INSTALL_ROOT}
work_root=$(mktemp -d "${TMPDIR:-/tmp}/victoria-apalache-install.XXXXXX")
archive="$work_root/$archive_name"
extract_root="$work_root/extract"
staged_install="$work_root/install"

cleanup() {
  rm -rf -- "$work_root"
}
trap cleanup EXIT HUP INT TERM

if [ -e "$install_root" ]; then
  printf 'refusing to overwrite existing install root: %s\n' "$install_root" >&2
  exit 1
fi

mkdir -p "$extract_root" "$staged_install"
curl --fail --location --retry 3 --output "$archive" "$url"
printf '%s  %s\n' "$checksum" "$archive" | sha256sum --check --status
tar -xzf "$archive" -C "$extract_root"

binary=$(find "$extract_root" -type f -path '*/bin/apalache-mc' -print | head -n 1)
if [ -z "$binary" ]; then
  printf '%s\n' 'apalache-mc was not present in the verified archive' >&2
  exit 1
fi

distribution=$(CDPATH= cd -- "$(dirname -- "$binary")/.." && pwd)
cp -R "$distribution"/. "$staged_install"/
chmod +x "$staged_install/bin/apalache-mc"
"$staged_install/bin/apalache-mc" version
mv "$staged_install" "$install_root"
