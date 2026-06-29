#!/bin/bash
# Host pre-flight for the device patch: transplant Panel.label + dispatch repoint
# + invoke panelStatus() on the no-JIT runtime. PASS = slots=1 and
# panelStatus() => render-> PATCH-UI-FIXED (mirrors the device boot hook exactly).
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
ANALYZE="$OUT/analyze_snapshot"
WORK="${WORK:-/tmp/sankofa_dispatch_devicepatch}"   # build_patch.sh already populated this
DI="dev-dart-app:/data/di.yaml"

[ -f "$WORK/patch.bytecode" ] || { echo "run build_patch.sh first"; exit 2; }
cd "$WORK"

echo "### base AOT (flag-free) ###"
"$AOTRT" "$GENKERNEL" --target vm --packages "$PKGCFG" -Ddart.vm.product=true \
  --aot --no-embed-sources --platform "$PLATFORM" --output base-aot.dill \
  --filesystem-root "$WORK" --filesystem-scheme dev-dart-app \
  --dynamic-interface "$DI" "dev-dart-app:/data/base.dart"
"$GENSNAP" --snapshot_kind=app-aot-elf --elf=base.aot base-aot.dill

echo "### APPLY (no flag, no JIT): transplant Panel.label + repoint + panelStatus ###"
echo "    PASS: 'transplant OK: Panel.label (dispatch slots=1)' + 'panelStatus() => render-> PATCH-UI-FIXED'"
SANKOFA_SKIP_BEFORE=1 "$ANALYZE" --bytecode_patch="$WORK/patch.bytecode" \
  --patch_fns=Panel.label --patch_invoke=panelStatus "$WORK/base.aot"
