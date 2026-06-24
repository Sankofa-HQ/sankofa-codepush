#!/bin/bash
#
# Sankofa CodePush — prove the CHANGED-code leg of iOS code-push, device-free.
#
# The iOS code-push model has two legs:
#   1. UNCHANGED code -> reuse the base app's AOT (the "fuse"; proven by
#      analyze_snapshot --fusion_selftest, see ../../../sankofa-dart-sdk
#      runtime/bin/analyze_snapshot.cc + ENGINE_FUSION_TASKS_6_7.md).
#   2. CHANGED code -> ship as DOWNLOADED BYTECODE and run it through the VM
#      interpreter, NEVER as native instructions (App Store iOS forbids
#      PROT_EXEC without a JIT entitlement). THIS script proves leg #2.
#
# It runs entirely on the host using OUR OWN engine's `dartaotruntime_product`
# — the precompiled (AOT) runtime, which has NO JIT. So any bytecode it runs
# MUST be interpreted: exactly the iOS constraint. If the test prints the
# success token, our vanilla sankofa-flutter engine build can execute
# downloaded bytecode with no JIT — the same capability β.3 proved on a real
# iPhone, here re-proven in our own build with zero device.
#
# Pipeline (mirrors pkg/dynamic_modules/test/runner/vm.dart, AOT mode):
#   gen_kernel (--aot, --dynamic-interface)  -> main_aot.dill
#   gen_kernel (--no-aot)                    -> main_no_aot.dill   (import-dill)
#   gen_snapshot (app-aot-elf)               -> main.snapshot      (base app)
#   dart2bytecode (--import-dill, --validate)-> entry1.dart.bytecode (the patch)
#   dartaotruntime_product main.snapshot     -> loads + interprets the bytecode
#
# Prereqs: build these targets once in the engine out dir (they must match the
# CURRENT libdart snapshot version — rebuild after any VM source change):
#   ninja -C out/mac_release_arm64 dartaotruntime_product gen_snapshot \
#         vm_platform_product.dill gen/gen_kernel_aot.dart.snapshot \
#         gen/dart2bytecode.dart.snapshot
#
# Usage: ENGINE_SRC=/path/to/sankofa-flutter/engine/src ./prove_nojit_bytecode.sh
set -e

ENGINE_SRC="${ENGINE_SRC:-$HOME/Developer/Projects/Sankofa/flutter-deploy/sankofa-flutter/engine/src}"
OUT="$ENGINE_SRC/out/mac_release_arm64"
DART="$ENGINE_SRC/flutter/third_party/dart"
TESTROOT="$DART/pkg/dynamic_modules/test"
PKGCFG="$DART/.dart_tool/package_config.json"
WORK="${WORK:-/tmp/sankofa_nojit_proof}"
TEST="${TEST:-core_api}"

AOTRT="$OUT/dartaotruntime_product"
GENKERNEL="$OUT/gen/gen_kernel_aot.dart.snapshot"
DART2BC="$OUT/gen/dart2bytecode.dart.snapshot"
GENSNAP="$OUT/gen_snapshot"
PLATFORM="$OUT/vm_platform_product.dill"

for f in "$AOTRT" "$GENKERNEL" "$DART2BC" "$GENSNAP" "$PLATFORM"; do
  [ -e "$f" ] || { echo "MISSING: $f  (build it first — see header)"; exit 2; }
done

rm -rf "$WORK"; mkdir -p "$WORK/modules"; cd "$WORK"

echo "### 1. AOT kernel (main.dart) with dynamic interface ###"
"$AOTRT" "$GENKERNEL" --target vm --packages "$PKGCFG" \
  -Ddart.vm.profile=false -Ddart.vm.product=true \
  --aot --no-embed-sources --platform "$PLATFORM" --output main_aot.dill \
  --filesystem-root "$TESTROOT" --filesystem-scheme dev-dart-app \
  --dynamic-interface "dev-dart-app:/data/$TEST/dynamic_interface.yaml" \
  "dev-dart-app:/data/$TEST/main.dart"

echo "### 2. no-AOT kernel (for import-dill) ###"
"$AOTRT" "$GENKERNEL" --target vm --packages "$PKGCFG" \
  -Ddart.vm.profile=false -Ddart.vm.product=true \
  --no-aot --no-embed-sources --platform "$PLATFORM" --output main_no_aot.dill \
  --filesystem-root "$TESTROOT" --filesystem-scheme dev-dart-app \
  --dynamic-interface "dev-dart-app:/data/$TEST/dynamic_interface.yaml" \
  "dev-dart-app:/data/$TEST/main.dart"

echo "### 3. AOT snapshot (the base app — what ships in the IPA) ###"
"$GENSNAP" --snapshot_kind=app-aot-elf --elf=main.snapshot main_aot.dill

echo "### 4. compile the dynamic module -> BYTECODE (this is the patch) ###"
"$AOTRT" "$DART2BC" --platform "$PLATFORM" --target vm --packages "$PKGCFG" \
  -Ddart.vm.profile=false -Ddart.vm.product=true \
  --import-dill main_no_aot.dill \
  --validate "dev-dart-app:/data/$TEST/dynamic_interface.yaml" \
  --filesystem-root "$TESTROOT" --filesystem-scheme dev-dart-app \
  --output modules/entry1.dart.bytecode --prefix-library-uris import/prefix \
  "dev-dart-app:/data/$TEST/modules/entry1.dart"

echo "### artifacts (note the tiny bytecode patch size) ###"
ls -la main.snapshot modules/entry1.dart.bytecode

echo "### 5. RUN on dartaotruntime_product (NO JIT) — expect success token ###"
"$AOTRT" main.snapshot
