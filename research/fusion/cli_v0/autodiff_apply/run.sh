#!/bin/bash
# #4 host proof: compile the CHANGED APP SOURCE to bytecode and same-name
# transplant an app METHOD (Panel.label) onto the base. This is what
# `sankofa patch ios` will do: dev edits normal code -> compile it -> transplant
# the changed methods (from the auto-diff manifest) -> reroute. PASS =
# "panelStatus() => render-> PATCH-UI-FIXED".
set -e
ENGINE_SRC="${ENGINE_SRC:-$HOME/Developer/Projects/Sankofa/flutter-deploy/sankofa-flutter/engine/src}"
OUT="$ENGINE_SRC/out/mac_release_arm64"
DART="$ENGINE_SRC/flutter/third_party/dart"
PKGCFG="$DART/.dart_tool/package_config.json"
HERE="$(cd "$(dirname "$0")" && pwd)"
AOTRT="$OUT/dartaotruntime_product"
GENKERNEL="$OUT/gen/gen_kernel_aot.dart.snapshot"
DART2BC="$OUT/gen/dart2bytecode.dart.snapshot"
GENSNAP="$OUT/gen_snapshot"
PLATFORM="$OUT/vm_platform_product.dill"
ANALYZE="$OUT/analyze_snapshot"
WORK="${WORK:-/tmp/sankofa_autodiff4}"
DI="dev-dart-app:/data/di.yaml"
rm -rf "$WORK"; mkdir -p "$WORK/data"
cp "$HERE/base.dart" "$HERE/patch.dart" "$HERE/di.yaml" "$WORK/data/"
cd "$WORK"

echo "### 1. base AOT (the deployed app) ###"
"$AOTRT" "$GENKERNEL" --target vm --packages "$PKGCFG" -Ddart.vm.product=true \
  --aot --no-embed-sources --platform "$PLATFORM" --output base_aot.dill \
  --filesystem-root "$WORK" --filesystem-scheme dev-dart-app \
  --dynamic-interface "$DI" "dev-dart-app:/data/base.dart"
"$GENSNAP" --snapshot_kind=app-aot-elf --elf=base.aot base_aot.dill

echo "### 2. base no-aot kernel (for --import-dill) ###"
"$AOTRT" "$GENKERNEL" --target vm --packages "$PKGCFG" -Ddart.vm.product=true \
  --no-aot --no-embed-sources --platform "$PLATFORM" --output base_noaot.dill \
  --filesystem-root "$WORK" --filesystem-scheme dev-dart-app \
  --dynamic-interface "$DI" "dev-dart-app:/data/base.dart"

echo "### 3. compile the CHANGED APP SOURCE -> bytecode module ###"
"$AOTRT" "$DART2BC" --platform "$PLATFORM" --target vm --packages "$PKGCFG" \
  -Ddart.vm.product=true --import-dill base_noaot.dill \
  --validate "$DI" \
  --filesystem-root "$WORK" --filesystem-scheme dev-dart-app \
  --output patch.bytecode --prefix-library-uris sankofa/patch \
  "dev-dart-app:/data/patch.dart"
ls -la patch.bytecode

echo "### 4. SAME-NAME transplant of the app method Panel.label + invoke panelStatus ###"
echo "    PASS: 'panelStatus() => render-> PATCH-UI-FIXED'"
SANKOFA_SKIP_BEFORE=1 "$ANALYZE" --bytecode_patch="$WORK/patch.bytecode" \
  --patch_fns="Panel.label" --patch_invoke=panelStatus "$WORK/base.aot"
echo "### exit=$? ###"
