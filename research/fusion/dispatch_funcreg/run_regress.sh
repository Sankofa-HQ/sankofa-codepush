#!/bin/bash
# Sankofa dispatch-funcreg REGRESSION: build the polymorphic app with the NEW
# engine (interleaved dispatch table + stride-2/R8 EmitDispatchTableCall) and run
# it on the no-JIT precompiled runtime. PASS = prints woof/meow/moo (normal
# virtual dispatch still correct through the new dispatch-table layout).
set -e
ENGINE_SRC="${ENGINE_SRC:-$HOME/Developer/Projects/Sankofa/flutter-deploy/sankofa-flutter/engine/src}"
OUT="$ENGINE_SRC/out/mac_release_arm64"
DART="$ENGINE_SRC/flutter/third_party/dart"
PKGCFG="$DART/.dart_tool/package_config.json"
HERE="$(cd "$(dirname "$0")" && pwd)"
AOTRT="$OUT/dartaotruntime_product"
GENKERNEL="$OUT/gen/gen_kernel_aot.dart.snapshot"
GENSNAP="$OUT/gen_snapshot"
PLATFORM="$OUT/vm_platform_product.dill"
WORK="${WORK:-/tmp/sankofa_dispatch_regress}"

for f in "$AOTRT" "$GENKERNEL" "$GENSNAP" "$PLATFORM"; do
  [ -e "$f" ] || { echo "MISSING: $f"; exit 2; }
done

rm -rf "$WORK"; mkdir -p "$WORK/data"
cp "$HERE/regress.dart" "$WORK/data/regress.dart"
cd "$WORK"

echo "### 1. AOT kernel ###"
"$AOTRT" "$GENKERNEL" --target vm --packages "$PKGCFG" \
  -Ddart.vm.product=true \
  --aot --no-embed-sources --platform "$PLATFORM" --output regress.dill \
  --filesystem-root "$WORK" --filesystem-scheme dev-dart-app \
  "dev-dart-app:/data/regress.dart"

echo "### 2. AOT snapshot (NEW gen_snapshot: interleaved dispatch table) ###"
"$GENSNAP" --snapshot_kind=app-aot-elf --elf=regress.aot regress.dill

echo "### 3. RUN on no-JIT dartaotruntime_product ###"
echo "    expect: SANKOFA_DISPATCH_REGRESS_OK then woof / meow / moo"
"$AOTRT" regress.aot
