#!/bin/bash
# Build the dispatch-funcreg device patch.bytecode (Panel.label -> PATCH-UI-FIXED)
# with the NEW toolchain (version-matched to the iOS engine). Mirrors the proven
# make_and_apply_patch flow: base no-aot kernel -> dart2bytecode the patch module.
set -e
ENGINE_SRC="${ENGINE_SRC:-$HOME/Developer/Projects/Sankofa/flutter-deploy/sankofa-flutter/engine/src}"
OUT="$ENGINE_SRC/out/mac_release_arm64"
DART="$ENGINE_SRC/flutter/third_party/dart"
PKGCFG="$DART/.dart_tool/package_config.json"
HERE="$(cd "$(dirname "$0")" && pwd)"
AOTRT="$OUT/dartaotruntime_product"
GENKERNEL="$OUT/gen/gen_kernel_aot.dart.snapshot"
DART2BC="$OUT/gen/dart2bytecode.dart.snapshot"
PLATFORM="$OUT/vm_platform_product.dill"
WORK="${WORK:-/tmp/sankofa_dispatch_devicepatch}"
DI="dev-dart-app:/data/di.yaml"

for f in "$AOTRT" "$GENKERNEL" "$DART2BC" "$PLATFORM"; do
  [ -e "$f" ] || { echo "MISSING: $f"; exit 2; }
done

rm -rf "$WORK"; mkdir -p "$WORK/data"
cp "$HERE/base.dart" "$HERE/patch_module.dart" "$HERE/di.yaml" "$WORK/data/"
cd "$WORK"

echo "### base no-aot kernel (for import-dill) ###"
"$AOTRT" "$GENKERNEL" --target vm --packages "$PKGCFG" -Ddart.vm.product=true \
  --no-aot --no-embed-sources --platform "$PLATFORM" --output base-noaot.dill \
  --filesystem-root "$WORK" --filesystem-scheme dev-dart-app \
  --dynamic-interface "$DI" "dev-dart-app:/data/base.dart"

echo "### patch -> bytecode ###"
"$AOTRT" "$DART2BC" --platform "$PLATFORM" --target vm --packages "$PKGCFG" \
  -Ddart.vm.product=true --import-dill base-noaot.dill \
  --validate "$DI" \
  --filesystem-root "$WORK" --filesystem-scheme dev-dart-app \
  --output patch.bytecode --prefix-library-uris sankofa/patch \
  "dev-dart-app:/data/patch_module.dart"

ls -la "$WORK/patch.bytecode"
cp "$WORK/patch.bytecode" "$HERE/patch.bytecode"
echo "patch.bytecode -> $HERE/patch.bytecode"
