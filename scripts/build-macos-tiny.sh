#!/usr/bin/env bash
set -euo pipefail

export LANG=${LANG:-en_US.UTF-8}
export LC_ALL=${LC_ALL:-en_US.UTF-8}

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
arch=$(uname -m)
output=${1:-"$root/dist/macos-$arch-release"}
case "$output" in
  "$root"/dist/*) ;;
  *) echo "output must be inside $root/dist" >&2; exit 2 ;;
esac

for command in cargo flutter flutter_rust_bridge_codegen python3 xcodebuild xcrun; do
  command -v "$command" >/dev/null || { echo "Missing required command: $command" >&2; exit 1; }
done
xcodebuild -version >/dev/null

cd "$root"
(cd flutter && flutter pub get)
llvm_path=${RUSTDESK_LLVM_PATH:-}
if [[ -z "$llvm_path" ]]; then
  clang_path=$(xcrun --find clang)
  llvm_path=$(cd "$(dirname "$clang_path")/.." && pwd)
fi
[[ -f "$llvm_path/lib/libclang.dylib" ]] || {
  echo "libclang.dylib not found under $llvm_path; set RUSTDESK_LLVM_PATH" >&2
  exit 1
}
macos_sdk=$(xcrun --sdk macosx --show-sdk-path)
flutter_rust_bridge_codegen \
  --rust-input ./src/flutter_ffi.rs \
  --dart-output ./flutter/lib/generated_bridge.dart \
  --llvm-path "$llvm_path" \
  --llvm-compiler-opts="-isysroot $macos_sdk"
python3 ./build.py --flutter --rustdesk-tiny

source_app="$root/flutter/build/macos/Build/Products/Release/RustDesk.app"
[[ -d "$source_app" ]] || { echo "RustDesk.app was not produced" >&2; exit 1; }
[[ -x "$source_app/Contents/MacOS/RustDesk" ]] || {
  echo "RustDesk executable was not produced" >&2
  exit 1
}
[[ -x "$source_app/Contents/MacOS/service" ]] || {
  echo "RustDesk service was not embedded" >&2
  exit 1
}

rm -rf "$output"
mkdir -p "$output"
app="$output/RustDeskTiny.app"
cp -a "$source_app" "$app"
mv "$app/Contents/MacOS/RustDesk" "$app/Contents/MacOS/RustDeskTiny"

info_plist="$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable RustDeskTiny' "$info_plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier top.p2premote.rustdesktiny' "$info_plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName RustDeskTiny' "$info_plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName RustDeskTiny' "$info_plist" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c 'Add :CFBundleDisplayName string RustDeskTiny' "$info_plist"

cp LICENCE "$output/"
printf 'RustDeskTiny app: %s\n' "$app"
printf 'Sign and package this app with the upstream macOS signing workflow.\n'
