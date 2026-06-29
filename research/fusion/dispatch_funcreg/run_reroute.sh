#!/bin/bash
# Sankofa dispatch-funcreg REROUTE proof (the real one): build the base app with
# NO flag (normal dispatch-table virtual calls, compiled with the new
# interleaved-table / R8-loading convention), transplant Widget.build to
# bytecode, repoint its dispatch slots to the InterpretCall trampoline, and call
# renderNew() (render -> w.build() via the dispatch table from UNCHANGED base AOT).
# PASS = "after dispatch repoint: renderNew()=render-> PATCH-UI-FIXED" with NO
# flag, NO JIT.
set -e
ENGINE_SRC="${ENGINE_SRC:-$HOME/Developer/Projects/Sankofa/flutter-deploy/sankofa-flutter/engine/src}"
OUT="$ENGINE_SRC/out/mac_release_arm64"
DART="$ENGINE_SRC/flutter/third_party/dart"
PKGCFG="$DART/.dart_tool/package_config.json"
SRC="/Users/saytoonz/Developer/Projects/Sankofa/flutter-deploy/sankofa-codepush/research/fusion/override_in_place/data/t1"
AOTRT="$OUT/dartaotruntime_product"
GENKERNEL="$OUT/gen/gen_kernel_aot.dart.snapshot"
DART2BC="$OUT/gen/dart2bytecode.dart.snapshot"
GENSNAP="$OUT/gen_snapshot"
PLATFORM="$OUT/vm_platform_product.dill"
ANALYZE="$OUT/analyze_snapshot"
WORK="${WORK:-/tmp/sankofa_dispatch_reroute}"
TEST=t1

for f in "$AOTRT" "$GENKERNEL" "$DART2BC" "$GENSNAP" "$PLATFORM" "$ANALYZE"; do
  [ -e "$f" ] || { echo "MISSING: $f"; exit 2; }
done
[ -d "$SRC" ] || { echo "MISSING src dir: $SRC"; exit 2; }

rm -rf "$WORK"; mkdir -p "$WORK/data/$TEST/modules"
cp "$SRC/main.dart" "$WORK/data/$TEST/main.dart"
cp "$SRC/dynamic_interface.yaml" "$WORK/data/$TEST/dynamic_interface.yaml"
cp "$SRC/modules/patch.dart" "$WORK/data/$TEST/modules/patch.dart"
cd "$WORK"
DI="dev-dart-app:/data/$TEST/dynamic_interface.yaml"

echo "### 1. AOT kernel ###"
"$AOTRT" "$GENKERNEL" --target vm --packages "$PKGCFG" -Ddart.vm.product=true \
  --aot --no-embed-sources --platform "$PLATFORM" --output main_aot.dill \
  --filesystem-root "$WORK" --filesystem-scheme dev-dart-app \
  --dynamic-interface "$DI" "dev-dart-app:/data/$TEST/main.dart"

echo "### 2. no-AOT kernel (for import-dill) ###"
"$AOTRT" "$GENKERNEL" --target vm --packages "$PKGCFG" -Ddart.vm.product=true \
  --no-aot --no-embed-sources --platform "$PLATFORM" --output main_no_aot.dill \
  --filesystem-root "$WORK" --filesystem-scheme dev-dart-app \
  --dynamic-interface "$DI" "dev-dart-app:/data/$TEST/main.dart"

echo "### 3. base AOT snapshot — NO SANKOFA_NO_TABLE_DISPATCH (flag-free!) ###"
"$GENSNAP" --snapshot_kind=app-aot-elf --elf=base.aot main_aot.dill

echo "### 4. patch -> bytecode ###"
"$AOTRT" "$DART2BC" --platform "$PLATFORM" --target vm --packages "$PKGCFG" \
  -Ddart.vm.product=true --import-dill main_no_aot.dill \
  --validate "$DI" \
  --filesystem-root "$WORK" --filesystem-scheme dev-dart-app \
  --output patch.bytecode --prefix-library-uris sankofa/patch \
  "dev-dart-app:/data/$TEST/modules/patch.dart"

echo "### 5. APPLY (NO JIT, NO flag): transplant + DISPATCH REPOINT + renderNew ###"
echo "    PASS: 'after dispatch repoint: renderNew()=render-> PATCH-UI-FIXED'"
"$ANALYZE" --bytecode_patch="$WORK/patch.bytecode" "$WORK/base.aot"
