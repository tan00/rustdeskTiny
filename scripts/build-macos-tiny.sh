#!/usr/bin/env bash
set -euo pipefail

export LANG=${LANG:-en_US.UTF-8}
export LC_ALL=${LC_ALL:-en_US.UTF-8}

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
output=${1:-"$root/dist/macos-universal-release"}
case "$output" in
  "$root"/dist/*) ;;
  *) echo "output must be inside $root/dist" >&2; exit 2 ;;
esac

for command in cargo rustup flutter flutter_rust_bridge_codegen lipo file xcodebuild xcrun; do
  command -v "$command" >/dev/null || { echo "Missing required command: $command" >&2; exit 1; }
done
: "${VCPKG_ROOT:?VCPKG_ROOT must point to a vcpkg installation containing x64-osx and arm64-osx packages}"
xcodebuild -version >/dev/null
rust_toolchain=${RUSTDESK_RUST_TOOLCHAIN:-1.81.0}
rustup run "$rust_toolchain" rustc --version >/dev/null 2>&1 || {
  echo "Missing Rust toolchain: $rust_toolchain" >&2
  exit 1
}
rustup target add --toolchain "$rust_toolchain" x86_64-apple-darwin aarch64-apple-darwin

build_dir=$(mktemp -d "${TMPDIR:-/tmp}/rustdesktiny-macos.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT

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

build_arch() {
  local triple=$1
  local arch=$2
  local triplet=$3
  local arch_dir="$build_dir/$arch"
  mkdir -p "$arch_dir" target/release

  MACOSX_DEPLOYMENT_TARGET=12.3 \
  VCPKG_DEFAULT_TRIPLET="$triplet" \
    cargo "+$rust_toolchain" build --locked --release --target "$triple" \
      --features rustdesk-tiny,flutter --lib --bin service
  cp "target/$triple/release/liblibrustdesk.dylib" target/release/librustdesk.dylib
  (
    cd flutter
    MACOSX_DEPLOYMENT_TARGET=12.3 ARCHS="$arch" ONLY_ACTIVE_ARCH=YES \
      flutter build macos --release
  )
  cp -a flutter/build/macos/Build/Products/Release/RustDesk.app "$arch_dir/RustDesk.app"
  cp "target/$triple/release/service" "$arch_dir/service"
}

build_arch x86_64-apple-darwin x86_64 x64-osx
build_arch aarch64-apple-darwin arm64 arm64-osx

rm -rf "$output"
mkdir -p "$output"
cp -a "$build_dir/x86_64/RustDesk.app" "$output/RustDeskTiny.app"

while IFS= read -r -d '' x86_file; do
  relative=${x86_file#"$build_dir/x86_64/RustDesk.app/"}
  arm_file="$build_dir/arm64/RustDesk.app/$relative"
  if file "$x86_file" | grep -q 'Mach-O'; then
    [[ -f "$arm_file" ]] || { echo "Missing arm64 Mach-O counterpart: $relative" >&2; exit 1; }
    lipo -create "$x86_file" "$arm_file" \
      -output "$output/RustDeskTiny.app/$relative"
    lipo "$output/RustDeskTiny.app/$relative" -verify_arch x86_64 arm64
  fi
done < <(find "$build_dir/x86_64/RustDesk.app" -type f -print0)

lipo -create "$build_dir/x86_64/service" "$build_dir/arm64/service" \
  -output "$output/RustDeskTiny.app/Contents/MacOS/service"
lipo "$output/RustDeskTiny.app/Contents/MacOS/service" -verify_arch x86_64 arm64

mv "$output/RustDeskTiny.app/Contents/MacOS/RustDesk" \
   "$output/RustDeskTiny.app/Contents/MacOS/RustDeskTiny"
info_plist="$output/RustDeskTiny.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable RustDeskTiny' "$info_plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier top.p2premote.rustdesktiny' "$info_plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName RustDeskTiny' "$info_plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName RustDeskTiny' "$info_plist" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c 'Add :CFBundleDisplayName string RustDeskTiny' "$info_plist"
cp LICENCE "$output/"
printf 'RustDeskTiny universal output: %s\n' "$output"
