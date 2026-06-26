#!/bin/bash
#
# Sankofa CodePush CLI v0 — the FULL automated loop, device-free:
#   change code -> DIFF (changed set) -> compile patch bytecode -> APPLY -> run.
#
# Mirrors the proven override_in_place build (filesystem-scheme + dynamic-interface
# so the bytecode module resolves dart:core consistently against the base), then:
# 1. base.aot (+ base no-aot kernel for import-dill).
# 2. DIFF base vs the changed app (subgraph_hash set-diff) -> changed_manifest.json.
# 3. compile the extracted changed-set module (patch_module.dart) -> bytecode.
# 4. APPLY: analyze_snapshot loads base.aot (executable) + the bytecode module,
#    transplants each manifest target (AttachBytecode), invokes caller(), prints.
#    Runs on the precompiled (NO-JIT) runtime -> the new bodies are interpreted.
#
# Usage: ENGINE_SRC=... ./make_and_apply_patch.sh
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
WORK="${WORK:-/tmp/sankofa_cli_v0_loop}"
DI="dev-dart-app:/data/di.yaml"
# Parameterized: pick the demo via env (defaults = the compute string-change demo).
BASE_SRC="${BASE_SRC:-base}"        # full base app
PATCH_SRC="${PATCH_SRC:-patchA}"    # full patched app (for the diff)
MODULE_SRC="${MODULE_SRC:-patch_module}"  # extracted changed-set module (bytecode)
INVOKE="${INVOKE:-caller}"          # fn to invoke before/after
rm -rf "$WORK"; mkdir -p "$WORK/data"
cp "$HERE"/data/*.dart "$HERE/data/di.yaml" "$WORK/data/"
cd "$WORK"

genk () {  # $1=src-basename $2=out.dill $3=aot|no-aot
  "$AOTRT" "$GENKERNEL" --target vm --packages "$PKGCFG" -Ddart.vm.product=true \
    --$3 --no-embed-sources --platform "$PLATFORM" --output "$WORK/$2" \
    --filesystem-root "$WORK" --filesystem-scheme dev-dart-app \
    --dynamic-interface "$DI" "dev-dart-app:/data/$1.dart" >/dev/null
}
analyze () {  # $1=tag.aot $2=tag.json
  "$ANALYZE" --shorebird --out="$WORK/$2" "$WORK/$1" >/dev/null 2>&1
}

echo "### 1+2. build base.aot, diff $BASE_SRC vs $PATCH_SRC -> changed manifest ###"
genk "$BASE_SRC" base-aot.dill aot
"$GENSNAP" --snapshot_kind=app-aot-elf --elf="$WORK/base.aot" "$WORK/base-aot.dill" >/dev/null 2>&1
genk "$PATCH_SRC" patch-aot.dill aot
"$GENSNAP" --snapshot_kind=app-aot-elf --elf="$WORK/patch.aot" "$WORK/patch-aot.dill" >/dev/null 2>&1
analyze base.aot base.json
analyze patch.aot patch.json
genk "$BASE_SRC" base-noaot.dill no-aot   # for dart2bytecode --import-dill

FNS=$(python3 - "$WORK/base.json" "$WORK/patch.json" "$WORK/changed_manifest.json" <<'PY'
import json, sys
base = json.load(open(sys.argv[1]))['functions']
patch = json.load(open(sys.argv[2]))['functions']
bh = {f['subgraph_hash'] for f in base}
# Scope to the APP library: our patch only ever transplants app functions as
# bytecode (SDK/platform code is in the base engine, never patched), so SDK hash
# drift across builds is irrelevant. Keep only app-library changed functions.
def is_app(f): return f.get('library_uri','').startswith('dev-dart-app')
changed = [f for f in patch if f['subgraph_hash'] not in bh and is_app(f)]
json.dump({"transplant":[{"name":f["name"],"library_uri":f.get("library_uri",""),
                          "subgraph_hash":f["subgraph_hash"]} for f in changed]},
          open(sys.argv[3],"w"), indent=2)
names = []
for f in changed:
    n = f['name']
    if n.startswith('_') or n in ('main','<stub>','<unknown>'): continue
    if n not in names: names.append(n)
print(','.join(names))
PY
)
echo "    diff says transplant: $FNS"

echo "### 3. generate self-contained module (manifest embedded) + compile -> patch.bytecode ###"
# The patch is ONE self-contained file: the changed-set functions + a generated
# _sankofaManifest() (the app-scoped changed names from the diff) + a dyn-module
# entry that retains the changed fns (tear-offs) + the manifest. The DEVICE boot
# hook calls _sankofaManifest() to learn what to transplant — no loose .names.
python3 - "$WORK/data/$MODULE_SRC.dart" "$WORK/data/_patch_full.dart" "$FNS" <<'PY'
import sys
mod_src, out, fns = sys.argv[1], sys.argv[2], sys.argv[3]
names = [n for n in fns.split(',') if n]
body = open(mod_src).read()
quoted = ', '.join("'%s'" % n for n in names)
tearoffs = ', '.join(names + ['_sankofaManifest'])
body += "\n@pragma('vm:entry-point')\nList<String> _sankofaManifest() => <String>[%s];\n" % quoted
body += "@pragma('dyn-module:entry-point')\nObject? _sankofaEntry() { final r = <Object?>[%s]; return r.length; }\n" % tearoffs
open(out, 'w').write(body)
PY
"$AOTRT" "$DART2BC" --platform "$PLATFORM" --target vm --packages "$PKGCFG" \
  -Ddart.vm.product=true --import-dill "$WORK/base-noaot.dill" \
  --filesystem-root "$WORK" --filesystem-scheme dev-dart-app --validate "$DI" \
  --output "$WORK/patch.bytecode" --prefix-library-uris sankofa/patch \
  "dev-dart-app:/data/_patch_full.dart"
ls -la "$WORK/patch.bytecode"

# Stage the DEVICE patch artifact = the SINGLE self-contained file the engine
# boot hook (DartIsolate::SankofaApplyBootPatch) reads via the updater's
# sankofa_next_boot_patch_path(). Manifest is embedded (_sankofaManifest()).
PATCH_OUT="$WORK/patch_out"; mkdir -p "$PATCH_OUT"
cp "$WORK/patch.bytecode" "$PATCH_OUT/sankofa_patch.bytecode"
echo "    device patch staged (single self-contained file):"
ls -la "$PATCH_OUT"

echo "### 4. APPLY (NO JIT): transplant manifest targets, invoke $INVOKE() ###"
"$ANALYZE" --bytecode_patch="$WORK/patch.bytecode" --patch_fns="$FNS" \
  --patch_invoke="$INVOKE" "$WORK/base.aot"
