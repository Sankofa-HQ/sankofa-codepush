#!/bin/bash
#
# Sankofa CodePush — vendor the Rust updater (libupdater.a + the cbindgen C
# header) into the engine tree. `engine/.../third_party/updater/` is gitignored
# (prebuilt binaries), so this script is the reproducible source of truth: run it
# whenever the updater crate changes, then rebuild the engine.
#
# Produces, under $ENGINE/src/flutter/third_party/updater/ :
#   include/updater_engine.h                 (cbindgen, engine-facing C API)
#   lib/ios-arm64/libupdater.a               (aarch64-apple-ios)
#   lib/arm64-v8a/libupdater.a               (aarch64-linux-android)
#   lib/armeabi-v7a/libupdater.a             (armv7-linux-androideabi)
#   lib/x86_64/libupdater.a                  (x86_64-linux-android)
#
# Requires: rustup with the target triples installed:
#   rustup target add aarch64-apple-ios aarch64-linux-android \
#                     armv7-linux-androideabi x86_64-linux-android
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"            # .../sankofa-codepush/updater
LIB_DIR="$HERE/library"
ENGINE="${ENGINE:-$HOME/Developer/Projects/Sankofa/flutter-deploy/sankofa-flutter/engine}"
DST="$ENGINE/src/flutter/third_party/updater"

# triple -> engine abi dir
TRIPLES=(
  "aarch64-apple-ios:ios-arm64"
  "aarch64-linux-android:arm64-v8a"
  "armv7-linux-androideabi:armeabi-v7a"
  "x86_64-linux-android:x86_64"
)

echo "### header (cbindgen) -> $DST/include ###"
mkdir -p "$DST/include"
cp "$LIB_DIR/include/updater_engine.h" "$DST/include/updater_engine.h"

for entry in "${TRIPLES[@]}"; do
  triple="${entry%%:*}"; abi="${entry##*:}"
  echo "### build $triple -> lib/$abi ###"
  ( cd "$LIB_DIR" && cargo build --release --target "$triple" )
  mkdir -p "$DST/lib/$abi"
  cp "$HERE/target/$triple/release/libupdater.a" "$DST/lib/$abi/libupdater.a"
done

echo "### verify each lib exports the engine C API ###"
for entry in "${TRIPLES[@]}"; do
  abi="${entry##*:}"
  n=$(nm "$DST/lib/$abi/libupdater.a" 2>/dev/null | grep -cE ' T _?sankofa_init$' || true)
  echo "  lib/$abi/libupdater.a  sankofa_init: $n"
done
echo "DONE. Rebuild the engine to link the refreshed updater."
