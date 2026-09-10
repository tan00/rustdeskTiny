#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
output=${1:-"$root/dist/macos-$(uname -m)-release"}
case "$output" in
  "$root"/dist/*) ;;
  *) echo "output must be inside $root/dist" >&2; exit 2 ;;
esac

cd "$root"
flutter_rust_bridge_codegen \
  --rust-input ./src/flutter_ffi.rs \
  --dart-output ./flutter/lib/generated_bridge.dart
MACOSX_DEPLOYMENT_TARGET=10.14 cargo build --locked --release --features rustdesk-tiny,flutter
cp target/release/liblibrustdesk.dylib target/release/librustdesk.dylib
(cd flutter && flutter build macos --release)

source_app="$root/flutter/build/macos/Build/Products/Release/RustDesk.app"
rm -rf "$output"
mkdir -p "$output"
cp -a "$source_app" "$output/RustDeskTiny.app"
mv "$output/RustDeskTiny.app/Contents/MacOS/RustDesk" \
   "$output/RustDeskTiny.app/Contents/MacOS/RustDeskTiny"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable RustDeskTiny' \
  "$output/RustDeskTiny.app/Contents/Info.plist"
cp LICENCE "$output/"
printf 'RustDeskTiny output: %s\n' "$output"
