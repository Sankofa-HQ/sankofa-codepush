#!/bin/bash
#
# Sankofa CodePush — prove ARBITRARY-LOGIC code-push on a no-JIT runtime,
# device-free. This is the primitive that fixes CRASHES and ships large
# updates (not text/colors): a live AOT function is REPLACED by downloaded
# bytecode and runs the new body through the interpreter, no JIT.
#
# Mechanism (override-in-place):
#   1. Base app ships as normal AOT. `compute()` returns 'BASE'.
#   2. The patch = a tiny bytecode dynamic module (dart2bytecode) whose
#      `patched()` is the NEW body.
#   3. At runtime: Dart_LoadLibraryFromBytecode(patch) +
#      Dart_SankofaTransplantBytecode(base, "compute", patch, "patched")
#      calls Function::AttachBytecode → stores the bytecode AND points
#      compute's entry at the InterpretCall stub.
#   4. compute() now interprets the downloaded code: returns 'PATCH-CRASH-FIXED'.
#
# Runs on dartaotruntime_product / the analyze_snapshot embedder, which is the
# precompiled (AOT) runtime — NO JIT — so the new code MUST be interpreted.
# Exactly the iOS App Store constraint, proven on the host with zero device.
#
# Requires (built in the engine out dir, version-matched to current libdart —
# rebuild ALL of these after any dart_api.h / VM source change, else you get
# "Wrong full snapshot version"):
#   ninja -C out/mac_release_arm64 analyze_snapshot gen_snapshot \
#         dartaotruntime_product vm_platform_product.dill \
#         gen/gen_kernel_aot.dart.snapshot gen/dart2bytecode.dart.snapshot
#
# The transplant primitive lives in sankofa-dart-sdk:
#   runtime/vm/dart_api_impl.cc  Dart_SankofaTransplantBytecode
#   runtime/include/dart_api.h   (declaration)
#   runtime/bin/analyze_snapshot.cc  --bytecode_patch test mode
#
# Usage: ENGINE_SRC=/path/to/sankofa-flutter/engine/src ./prove_override_in_place.sh
set -e
ENGINE_SRC="${ENGINE_SRC:-$HOME/Developer/Projects/Sankofa/flutter-deploy/sankofa-flutter/engine/src}"
OUT="$ENGINE_SRC/out/mac_release_arm64"
DART="$ENGINE_SRC/flutter/third_party/dart"
PKGCFG="$DART/.dart_tool/package_config.json"
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${WORK:-/tmp/sankofa_override_proof}"
TEST=t1

AOTRT="$OUT/dartaotruntime_product"
GENKERNEL="$OUT/gen/gen_kernel_aot.dart.snapshot"
DART2BC="$OUT/gen/dart2bytecode.dart.snapshot"
GENSNAP="$OUT/gen_snapshot"
PLATFORM="$OUT/vm_platform_product.dill"
ANALYZE="$OUT/analyze_snapshot"

for f in "$AOTRT" "$GENKERNEL" "$DART2BC" "$GENSNAP" "$PLATFORM" "$ANALYZE"; do
  [ -e "$f" ] || { echo "MISSING: $f  (build it first — see header)"; exit 2; }
done

# Stage sources under WORK so the dev-dart-app filesystem-scheme resolves.
rm -rf "$WORK"; mkdir -p "$WORK/data/$TEST/modules"
cp "$HERE/data/$TEST/main.dart" "$WORK/data/$TEST/main.dart"
cp "$HERE/data/$TEST/dynamic_interface.yaml" "$WORK/data/$TEST/dynamic_interface.yaml"
cp "$HERE/data/$TEST/modules/patch.dart" "$WORK/data/$TEST/modules/patch.dart"
cd "$WORK"

echo "### 1. AOT kernel + dynamic interface ###"
"$AOTRT" "$GENKERNEL" --target vm --packages "$PKGCFG" \
  -Ddart.vm.profile=false -Ddart.vm.product=true \
  --aot --no-embed-sources --platform "$PLATFORM" --output main_aot.dill \
  --filesystem-root "$WORK" --filesystem-scheme dev-dart-app \
  --dynamic-interface "dev-dart-app:/data/$TEST/dynamic_interface.yaml" \
  "dev-dart-app:/data/$TEST/main.dart"

echo "### 2. no-AOT kernel (import-dill) ###"
"$AOTRT" "$GENKERNEL" --target vm --packages "$PKGCFG" \
  -Ddart.vm.profile=false -Ddart.vm.product=true \
  --no-aot --no-embed-sources --platform "$PLATFORM" --output main_no_aot.dill \
  --filesystem-root "$WORK" --filesystem-scheme dev-dart-app \
  --dynamic-interface "dev-dart-app:/data/$TEST/dynamic_interface.yaml" \
  "dev-dart-app:/data/$TEST/main.dart"

echo "### 3. base AOT snapshot (SANKOFA_NO_TABLE_DISPATCH=1 keeps instance calls"
echo "###    switchable so an UNCHANGED base caller can reach a transplanted"
echo "###    bytecode method = virtual entry-boundary proof, probe 3) ###"
SANKOFA_NO_TABLE_DISPATCH=1 "$GENSNAP" --snapshot_kind=app-aot-elf --elf=base.aot main_aot.dill

echo "### 4. patch -> BYTECODE (the downloaded crash-fix) ###"
"$AOTRT" "$DART2BC" --platform "$PLATFORM" --target vm --packages "$PKGCFG" \
  -Ddart.vm.profile=false -Ddart.vm.product=true \
  --import-dill main_no_aot.dill \
  --validate "dev-dart-app:/data/$TEST/dynamic_interface.yaml" \
  --filesystem-root "$WORK" --filesystem-scheme dev-dart-app \
  --output patch.bytecode --prefix-library-uris sankofa/patch \
  "dev-dart-app:/data/$TEST/modules/patch.dart"

echo "### artifacts ###"
ls -la base.aot patch.bytecode

echo "### 5. RUN (NO JIT): load patch, transplant onto live compute(), invoke ###"
echo "    expect: before=BASE, after=PATCH-CRASH-FIXED"
"$ANALYZE" --bytecode_patch="$WORK/patch.bytecode" "$WORK/base.aot"
