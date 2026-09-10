#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
output=${1:-"$root/dist/linux-$(uname -m)-release"}
case "$output" in
  "$root"/dist/*) ;;
  *) echo "output must be inside $root/dist" >&2; exit 2 ;;
esac

cd "$root"
flutter_rust_bridge_codegen \
  --rust-input ./src/flutter_ffi.rs \
  --dart-output ./flutter/lib/generated_bridge.dart
cargo build --locked --release --lib --features rustdesk-tiny,flutter
(cd flutter && flutter build linux --release)

rm -rf "$output"
mkdir -p "$output"
cp -a flutter/build/linux/*/release/bundle/. "$output/"
mv "$output/rustdesk" "$output/RustDeskTiny"
cp LICENCE "$output/"
printf 'RustDeskTiny output: %s\n' "$output"
