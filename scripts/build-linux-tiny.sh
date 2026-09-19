#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
output=${1:-"$root/dist"}
case "$output" in
  "$root"/dist|"$root"/dist/*) ;;
  *) echo "output must be inside $root/dist" >&2; exit 2 ;;
esac

for command in cargo flutter flutter_rust_bridge_codegen python3 dpkg-deb; do
  command -v "$command" >/dev/null || { echo "Missing required command: $command" >&2; exit 1; }
done

cd "$root"
rm -f rustdesk-*.deb
python3 ./build.py --flutter --rustdesk-tiny

shopt -s nullglob
packages=(rustdesk-*.deb)
if [[ ${#packages[@]} -ne 1 ]]; then
  echo "Expected exactly one rustdesk-*.deb, found ${#packages[@]}" >&2
  exit 1
fi

mkdir -p "$output"
package_name=${packages[0]#rustdesk-}
destination="$output/RustDeskTiny-$package_name"
mv "${packages[0]}" "$destination"
printf 'RustDeskTiny package: %s\n' "$destination"
