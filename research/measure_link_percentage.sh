#!/usr/bin/env bash
# Reproducible link-percentage harness for the iOS data-only port.
#
# Measures the core data-only patch metric end-to-end with whatever the
# local engine build currently supports: build base + patch AOTs, run
# `analyze_snapshot --shorebird` on both, group functions by subgraph_hash
# (the Linker.link algorithm, CODEPUSH_SPEC.md §4), and report what fraction
# of the patch reuses the base (= 1 - patch size). Higher is better.
#
# Usage:  ENG=<engine out dir> ./measure_link_percentage.sh
# Default ENG points at the local mac_release_arm64 build.
#
# It runs three comparisons that together locate the bottleneck:
#   A. base vs an INDEPENDENT recompile of identical source  (control)
#   B. base vs a recompile fed the base link data (alignment consumer)
#   C. self_hash vs subgraph_hash divergence (is it IL or layout?)
set -euo pipefail

ENG="${ENG:-$HOME/Developer/Projects/Sankofa/flutter-deploy/sankofa-flutter/engine/src/out/mac_release_arm64}"
DART="$ENG/dart-sdk/bin/dart"
AOTRT="$ENG/dart-sdk/bin/dartaotruntime"
WORK="${WORK:-$(mktemp -d)}"
mkdir -p "$WORK"
cd "$WORK"
echo "engine: $ENG"
echo "work:   $WORK"

cat > app.dart <<'DART'
int hot(int x) => (x * 31 + 7) ^ (x >> 3);
int layerC(int x) => hot(x) + hot(x + 1);
int layerB(int x) => layerC(x) + layerC(x * 2) + hot(x);
int layerA(int x) => layerB(x) + layerB(x + 5) + hot(x) + hot(x - 1);
String fmt(List<int> xs) => xs.map((e) => e.toString()).join(',');
void main() {
  final out = <int>[];
  for (var i = 0; i < 200; i++) out.add(layerA(i) + layerB(i) + layerC(i) + hot(i));
  final m = <String, int>{};
  for (final v in out) m['k${v % 17}'] = (m['k${v % 17}'] ?? 0) + v;
  print(fmt(out.take(5).toList())); print(m.length);
}
DART

aotk() { # aotk <src.dart> <out.dill>
  "$AOTRT" "$ENG/frontend_server_aot.dart.snapshot" --sdk-root "$ENG/" --target=vm \
    --aot --tfa --platform "$ENG/vm_platform.dill" --output-dill "$2" "$1" >/dev/null 2>&1
}

echo "── build base (emit link data) ──"
aotk app.dart app.aotk.dill
"$ENG/gen_snapshot" --snapshot_kind=app-aot-elf --elf=base.aot \
  --print_class_table_link_info_to=base.ct.link \
  --print_field_table_link_info_to=base.ft.link \
  --print_dispatch_table_link_info_to=base.dt.link app.aotk.dill >/dev/null 2>&1
"$ENG/analyze_snapshot" --shorebird --out=base.json base.aot >/dev/null 2>&1

echo "── A. independent recompile, NO alignment ──"
"$ENG/gen_snapshot" --snapshot_kind=app-aot-elf --elf=unaligned.aot app.aotk.dill >/dev/null 2>&1
"$ENG/analyze_snapshot" --shorebird --out=unaligned.json unaligned.aot >/dev/null 2>&1

echo "── B. recompile WITH base link data (alignment consumer) ──"
"$ENG/gen_snapshot" --snapshot_kind=app-aot-elf --elf=aligned.aot \
  --base_ct_link_data=base.ct.link --base_ft_link_data=base.ft.link \
  --base_dt_link_data=base.dt.link app.aotk.dill >/dev/null 2>&1
"$ENG/analyze_snapshot" --shorebird --out=aligned.json aligned.aot >/dev/null 2>&1

python3 - <<'PY'
import json
def fns(p): return json.load(open(p))["functions"]
def group(f):
    g={}
    for x in f: g.setdefault(x["subgraph_hash"],[]).append(x)
    return g
def linkpct(basef, patchf):
    bg=group(basef); m=sz=tot=0
    for x in patchf: tot+=x.get("size",0)
    for h,pl in group(patchf).items():
        bl=bg.get(h); n=min(len(pl),len(bl)) if bl else 0
        for i in range(len(pl)):
            if i<n: m+=1; sz+=pl[i].get("size",0)
    return m,len(patchf),100*sz/max(1,tot)
b=fns("base.json")
for label,p in [("A. unaligned recompile","unaligned.json"),("B. base-link-data aligned","aligned.json")]:
    m,t,pct=linkpct(b,fns(p))
    print(f"  {label:28s}: matched {m}/{t} = {100*m/t:5.2f}%   link% by size = {pct:5.2f}%")
# C. self vs subgraph divergence on the unaligned recompile
u=fns("unaligned.json"); bmap={(x['name'],x.get('index_in_entries')):x for x in b}
selfok=subdiff=0; chk=0
for x in u:
    bb=bmap.get((x['name'],x.get('index_in_entries')))
    if not bb: continue
    chk+=1
    if x.get('self_hash')==bb.get('self_hash'):
        selfok+=1
        if x.get('subgraph_hash')!=bb.get('subgraph_hash'): subdiff+=1
print(f"  C. self_hash identical: {selfok}/{chk}; self-same-but-subgraph-differs: {subdiff}")
print("  → high self-same + many subgraph-differs ⇒ layout (pool/class/field) divergence,")
print("    fixed by the patch-build alignment consumer (precompiler.cc), not by DD.")
PY
echo "artifacts in: $WORK"
