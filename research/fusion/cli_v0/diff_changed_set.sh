#!/bin/bash
#
# Sankofa CodePush CLI v0 — the DIFF brain. Given a base .dart and a patched
# .dart, compute the CHANGED FUNCTION SET = the functions that must ship in the
# bytecode patch. We use the analyzer's subgraph_hash, which is a transitive
# Merkle hash over the static call graph: a patch function is REUSED from base
# iff its subgraph_hash matches a base function; otherwise it changed. Because
# the hash folds in transitive CALLEE identity, changing one function also
# changes the subgraph_hash of every transitive STATIC caller — so the set-diff
# yields the changed fn + its static caller cascade for free, bounded at virtual
# dispatch edges (those are handled by the IC-reroute boundary mechanism).
#
# Usage: ENGINE_SRC=... ./diff_changed_set.sh base.dart patch.dart
set -e
ENGINE_SRC="${ENGINE_SRC:-$HOME/Developer/Projects/Sankofa/flutter-deploy/sankofa-flutter/engine/src}"
OUT="$ENGINE_SRC/out/mac_release_arm64"
DART="$ENGINE_SRC/flutter/third_party/dart"
PKGCFG="$DART/.dart_tool/package_config.json"
AOTRT="$OUT/dartaotruntime_product"
GENKERNEL="$OUT/gen/gen_kernel_aot.dart.snapshot"
GENSNAP="$OUT/gen_snapshot"
PLATFORM="$OUT/vm_platform_product.dill"
ANALYZE="$OUT/analyze_snapshot"
BASE_SRC="$1"; PATCH_SRC="$2"
WORK="${WORK:-/tmp/sankofa_cli_v0}"
rm -rf "$WORK"; mkdir -p "$WORK"

build_aot () {  # $1=src $2=tag
  local src="$1" tag="$2"
  "$AOTRT" "$GENKERNEL" --target vm --packages "$PKGCFG" \
    -Ddart.vm.profile=false -Ddart.vm.product=true \
    --aot --no-embed-sources --platform "$PLATFORM" \
    --output "$WORK/$tag.dill" "$src" >/dev/null
  "$GENSNAP" --snapshot_kind=app-aot-elf --elf="$WORK/$tag.aot" "$WORK/$tag.dill" >/dev/null
  "$ANALYZE" --shorebird --out="$WORK/$tag.json" "$WORK/$tag.aot" >/dev/null
}

echo "### building base + patch AOT, analyzing (--shorebird) ###"
build_aot "$BASE_SRC" base
build_aot "$PATCH_SRC" patch

python3 - "$WORK/base.json" "$WORK/patch.json" "$WORK/changed_manifest.json" <<'PY'
import json, sys
base = json.load(open(sys.argv[1]))['functions']
patch = json.load(open(sys.argv[2]))['functions']
base_hashes = {f['subgraph_hash'] for f in base}
# Changed = patch functions whose subgraph_hash is not present in base.
changed = [f for f in patch if f['subgraph_hash'] not in base_hashes]
# Scope to the APP library: a bytecode-transplant patch only ever ships app
# functions (SDK/platform code lives in the base engine, never patched), so SDK
# hash drift across independent builds is irrelevant noise. Keep app-lib fns.
def app(f):
    # App code = NOT the SDK/framework (those live in the base engine and are
    # never patched). Covers local file:// builds (dev), the dev-dart-app
    # fs-scheme (harness), and real apps (package:<app>/...).
    uri = f.get('library_uri', '')
    if not uri:
        return False
    if uri.startswith('dart:'):
        return False
    if uri.startswith('package:flutter') or uri.startswith('package:sky_engine'):
        return False
    return True
app_changed = [f for f in changed if app(f)]
changed = app_changed  # the manifest/link% are about the app patch set
print(f"base fns={len(base)} patch fns={len(patch)} | total changed (ship as bytecode)={len(changed)}")
print(f"link% by count = {100.0*(len(patch)-len(changed))/len(patch):.2f}%")
print("--- app-named changed functions (the bytecode cascade set) ---")
for f in sorted(app_changed, key=lambda x: x['name']):
    print(f"  {f['name']:14s} subgraph={f['subgraph_hash']}  self={f['self_hash']}")
other = len(changed) - len(app_changed)
if other:
    print(f"  (+{other} private/SDK fns whose transitive hash shifted)")
# Emit the patch manifest = the transplant target set the boot-time apply consumes
# (load patch bytecode module, AttachBytecode each named fn onto the base fn).
manifest = {
    "schema": 1,
    "link_pct": round(100.0*(len(patch)-len(changed))/len(patch), 2),
    "changed_count": len(changed),
    "transplant": [
        {"name": f["name"], "subgraph_hash": f["subgraph_hash"]}
        for f in changed
    ],
}
json.dump(manifest, open(sys.argv[3], "w"), indent=2)
print(f"\nwrote manifest -> {sys.argv[3]} ({len(changed)} transplant targets)")
PY
