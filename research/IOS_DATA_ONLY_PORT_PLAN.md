# iOS data-only code-push — cracked algorithm + port plan

Status: **DD algorithm cracked from Shorebird's real source** (engine patches in
`sankofa-flutter/engine/codepush-extraction/flutter/patches/` + decompiled
`research/aot-tools-decompile/CODEPUSH_SPEC.md` + live `~/.shorebird` CLI/aot-tools).
This is the actionable port spec. No more "DD is unknown."

## The mechanism (end to end)

`shorebird patch ios` → `flutter build ipa` → `gen_snapshot` patch ELF →
`aot_tools link` (9 sub-stages) → `out.vmcode` (LinkTable header, 4096-padded +
optimized AOT) → bidiff vs `dump_blobs` base → upload. Device: updater inflates
delta → `dlc.vmcode` → engine loads it.

**Deferred Dispatch (the cascade limiter):**
- Pass 1: `gen_snapshot … --print_dd_function_identity_to=App.dd_identity.link`
- `analyze_snapshot --compute_dd_table=App.dd.link --dd_caller_links=App.dd_callers.link --dd_max_bytes=10000 App_dd.so` → selects which high-fan-out functions get slots, within budget.
- `analyze_snapshot --compute_dd_slot_mapping=App.dd_slots.link --dd_table_data=… --dd_function_identity=…` → `DDSlotMapping{kernel_offset_to_slot}` (slot index keyed by stable kernel offset).
- Pass 2: `gen_snapshot … --dd_slot_mapping=App.dd_slots.link --print_dd_resolution_to=App.dd_resolution.tsv` → `FinalizeIndirectStaticCallTable` rewrites those functions' call sites to dispatch through the table. A patch then only repoints changed slots → 95%+ link percentage.

**Host linker (`Linker.link`, already present in `third_party/aot_tools/lib/src/linker.dart`):**
group base+patch Codes by `subgraph_hash` (post-order Merkle over transitive callees), map patch→base offsets in order, emit LinkTable (`count; (sim,cpu)×count; pad 4096`). Validates `snapshot_data` VM sections identical.

**Device execution on no-JIT iOS (THE CRUX — same as our proven β.3):**
`SHOREBIRD_USE_INTERPRETER=1` on iOS. Patch loaded `Dart_LoadELF(…, kReadOnly)`
(never PROT_EXEC). `Dart_CreateIsolateGroupWithBaseSnapshot(patch_data, patch_instr,
base_data, base_instr, …)` fuses patch+base; unchanged code runs base AOT, changed
code runs through `dart::Interpreter::Run`. No JIT, no executable mapping → App-Store legal.
This is exactly what `project_beta3_landed` / `project_codepush_beta3_cross_platform` proved on iPhone 14 Pro.

## What Sankofa already has (Phase B-1, branch `feat/phase7-on-3.44-redo` in sankofa-dart-sdk)
- ✅ `--shorebird` analyzer (`sankofa_snapshot_analyzer.cc`) — hashes present but FNV placeholder, subgraph_pp not transitive.
- ✅ 4 base emitters (`sankofa_codepush_emit.cc`): SCTL/SFTL/SOPL/SDTL.
- ✅ 4 patch readers + 5 lookup helpers (`sankofa_codepush_read.cc`).
- ✅ 1 precompiler hook: `ClassTable::Register` aligns class cid.
- ✅ host `Linker.link` + `SnapshotAnalysis`/`Code.fromJson` (inherited, intact).
- ✅ β.3 interpreter execution path on iOS (proven on device).

## Port checklist (Sankofa task → Shorebird source to translate). Requires engine rebuilds to validate.
1. Real IL-normalized Merkle `subgraph_hash` + transitive `subgraph_pp`/selectors/field_table in `sankofa_snapshot_analyzer.cc` → `CODEPUSH_SPEC.md §2`.
2. Wire gen_snapshot base-build link-info flags (`--print_{class_table,field_table,dispatch_table}_link_info_to`) to the existing `Dart_WriteSankofa*LinkData` emitters → patch `0007-f7db75e66.patch` `dumpLinkInfoArgs`.
3. Real DD passes in `analyze_snapshot.cc` (replace the 4 `WriteEmptyStubFile` stubs) + `DDSlotMapping`/`FinalizeIndirectStaticCallTable` in gen_snapshot → patch `0001-fe0104eba.patch` + `vm-side-api-surface.md §2-3`.
4. Field/pool/dispatch IL-alignment call sites in `precompiler.cc`/`object_pool.cc`/`dispatch_table.cc` (lookups already exist) → `CODEPUSH_SPEC.md §6b`.
5. aot_tools 9-stage `link` orchestrator (Sankofa drives the binaries itself) → `CODEPUSH_SPEC.md §4-5`, `~/.shorebird/.../aot_tools.dart:259-294`.
6. Apply the 12 engine patches onto `sankofa-flutter` (interpreter define, `.vmcode` loader `TryLoadFromPatch`, `Shorebird_SetBaseSnapshots`/`Shorebird_ReadLinkHeader`, base-snapshot plumbing) → patches `0006/0008/0009/0010/0012`.
7. Implement `Dart_CreateIsolateGroupWithBaseSnapshot`, `Shorebird_ReadLinkHeader`, `Shorebird_SetBaseSnapshots` in sankofa-dart-sdk → `vm-side-api-surface.md §1.2`.
8. Updater: wire engine first-frame `sankofa_report_launch_success` so the 10s grace-window crash detect (`lifecycle.rs:612-640`) goes live.

## Hardest remaining unknowns (now bounded, not blank)
- DD slot-allocation budgeting + `FinalizeIndirectStaticCallTable` body (contract known; body to reimplement) — task 3.
- Field/pool/dispatch alignment correctness (task 4) — most LOC.
- `Dart_CreateIsolateGroupWithBaseSnapshot` body in the VM (task 7) — the fusion.
The execution model (interpreter) is NOT an unknown — β.3 proved it on device.

## Progress (2026-06-22) — local build loop + analyzer-side done

The whole port is now built + validated **locally** (no rented servers): graft
the fork's codepush commits onto the engine's Dart 3.12.1 tree
(`engine/src/flutter/third_party/dart`) via `git diff <base>..<tip> | git apply
--3way`, then `ninja -C out/mac_release_arm64 analyze_snapshot gen_snapshot`.
Functional tests run by compiling a macOS AOT from any `app.dill`
(`gen_snapshot --snapshot_kind=app-aot-elf`) and analyzing it.

- ✅ **Task 1** (transitive `subgraph_pp`) — committed `1636818a04b`; validated on 9,155 fns.
- ✅ **Task 2** (base-build link-info emitters) — already wired in Phase B-1.
- ✅ **Task 3 PRODUCER** (`compute_dd_table`) — committed `eeefd9457d1`; the fan-in
  cascade limiter, keyed by `subgraph_hash`, formats `SDDT`/`SDCL`. Validated:
  1250 slots selected, top fan-in 5,688, on a real macOS AOT.

**Refined order for the rest** (the hard, coupled half): `compute_dd_slot_mapping`
must bridge `subgraph_hash` ↔ gen_snapshot's `dd_function_identity`, so it's part
of **Task 4** (the gen_snapshot consumer: `FinalizeIndirectStaticCallTable` +
field/pool/dispatch IL alignment in `precompiler.cc`). Then Task 6/7 (the 12
engine patches + `Dart_CreateIsolateGroupWithBaseSnapshot`) → iOS-config build →
on-device round-trip. The analyzer side is done; the precompiler/engine side is next.

## Progress (2026-06-23) — measured the link-% ceiling; bottleneck re-located

Ran the core data-only metric end-to-end on the live local build
(`research/measure_link_percentage.sh`, reproducible): build base + patch
AOTs, `analyze_snapshot --shorebird` both, group by `subgraph_hash`
(Linker.link §4), report reuse %.

**Grounded measurements (1379-fn macOS AOT, `mac_release_arm64`):**
- `--shorebird` is solid: **1379 functions, 100% distinct `subgraph_hash`**,
  `self_hash` **100% identical** across independent builds (per-function IL is
  fully deterministic). Task 1 confirmed good.
- Task 2 base-build emitters are **real**: `gen_snapshot
  --print_{class,field,dispatch}_table_link_info_to` produce `base.ct.link`
  (~42 KB), `base.ft.link` (~2 KB), `base.dt.link`.
- **Link ceiling without alignment = ~50%.** Recompiling *identical source*
  (zero code change) matches only **883/1382 fns (63.9%) / 49.5% by size**.
  **499 functions have identical `self_hash` but a different `subgraph_hash`** —
  pure object-pool/class/field **layout** divergence between independent
  compiles, not IL change.
- **The patch-build alignment consumer is a NO-OP.** Feeding the base link
  data back in (`gen_snapshot --base_ct_link_data --base_ft_link_data
  --base_dt_link_data`) is *accepted* but changes nothing: still 63.9% / 49.5%.
  The flag surface exists (Phase B-1) but the precompiler doesn't actually
  reuse the base offsets.

**Re-prioritization (the important conclusion):** the dominant link-% lever is
the **patch-build offset-alignment consumer** in `precompiler.cc` /
`object_pool.cc` / `class_table.cc` — making the patch build reuse the base's
pool/class/field/dispatch offsets so `subgraph_hash` matches. Until that works,
link% is capped ~50% on *any* patch and **DD cannot help** (DD breaks the
transitive cascade for high-fan-in functions, but here even zero-change
functions mismatch on layout). So **Task 4c (alignment) outranks
`compute_dd_slot_mapping` + the whole DD pipeline.** Do alignment first; measure
again with the harness (expect a jump toward ~100% on identical source); then DD
for the residual transitive cascade.

**Secondary gaps found:** `subgraph_selectors` + `subgraph_field_table` are not
emitted by `--shorebird` yet (0 across all fns) — needed to *verify* dispatch/
field alignment. And confirm `subgraph_hash` is computed over callee
*identities*, not build-volatile *offsets* (the 0%-diverged `subgraph_pp` vs
499 diverged `subgraph_hash` suggests the hash folds in something layout-
sensitive — worth auditing as it may inflate the mismatch).

### Follow-up experiment (same day): hash-stabilization is necessary but NOT sufficient

Tested whether the ~50% ceiling is a *hash* problem (cheap analyzer fix) or a
*layout* problem (the expensive precompiler consumer). Per-layer divergence on
an identical-source recompile (684 uniquely-named fns): `self_hash` diverged
**0**, `op_subgraph_hash` **60**, `subgraph_hash` **266** (= those 60 + **206
pure transitive cascade**). So the root is 60 `op_subgraph_hash` divergences.

`HashTaggedObjectIdentity` was folding in build-assigned class IDs (`c.id()`,
`owner.id()`) and `ComputeOpSubgraphHash` mixed in the raw pool *index* — all
build-volatile. Fixed both (stable scrubbed names + reference order; fork
`d7097e660a2`), rebuilt `analyze_snapshot`, re-measured:

- Hash *values* changed (confirmed in-binary), distinctness preserved (1382/1382,
  zero collisions). **But cross-build divergence is UNCHANGED: still 60 / 266.**

Conclusion: the divergence is in the **object-pool content itself** — two
independent compiles place/value pool entries differently — which a post-hoc
hash cannot normalize away. **There is no hash-only shortcut; the precompiler
offset-alignment consumer is genuinely required** (this is precisely why
Shorebird aligns the pool rather than just hashing cleverly). The committed hash
fix is a correct prerequisite (removes known-volatile inputs, satisfies the
Linker invariant for an *aligned* pool) but not a substitute.

**So the #1 task is unchanged and now doubly-confirmed:** implement the
patch-build alignment consumer — make the patch precompile REUSE the base's
object-pool / class / field / dispatch offsets (`object_pool.cc`,
`class_table.cc`, `precompiler.cc`, fed by `--base_*_link_data` which are
currently parsed-but-ignored). Open sub-question for that work: pinpoint which
pool-entry kinds diverge (instrument `ComputeOpSubgraphHash` to dump per-entry
type+identity for an op-diverged fn like `_unpackTypeArguments` and diff two
builds) — likely `RawValueAt` immediates and/or default-branch tagged objects
(TypeArguments/AbstractType/ICData).

### ⭐ BREAKTHROUGH (2026-06-24): the link works from a deterministic analyzer hash — NO precompiler alignment needed

**The two conclusions above are SUPERSEDED.** Ran the pinpoint sub-experiment
and it inverted the result. Instrumented `ComputeOpSubgraphHash`
(`SANKOFA_OP_DEBUG=<UserVisibleName>` dumps each referenced pool entry in code
order; dart-sdk `de89691ac2c`) and diffed two identical-source builds of
`_unpackTypeArguments`:

```
[0] imm t=2 raw=0x1024f4670  ≠  0x100d58670   ← THE divergence
[1..3] tagged id=…           =  …             ← all stable (cid→name fix worked)
```

`t=2` is **`kNativeFunction`** — the entry holds a raw engine C-function
ADDRESS (build/load-volatile), not a stable identity. Excluding the raw
address for `kNativeFunction` entries (keep the type marker) made the analyzer
hash fully cross-build deterministic. Re-measured (1382-fn AOT, harness):

| | matched | link% by size |
|---|---|---|
| identical-source recompile | **1382/1382 = 100%** (was 63.9%) | **100%** (was 49.5%) |
| change one leaf (`hot`) | 1375/1379 = 99.71% | **99.56%** — only 4 fns ship |

Distinctness preserved: subgraph_hash still **100% distinct, 0 collisions** —
so the matching is genuine, not loose. So: **the data-only link works from a
deterministic analyzer hash ALONE.** The ~50% ceiling was *entirely*
build-volatile HASH inputs (class cids → fixed; raw pool index → fixed;
**native-function addresses → the dominant one, now fixed**), NOT divergent
pool content. **The precompiler offset-alignment consumer is NOT required for
link matching** — scratch it from the critical path.

**Caveats (validate before declaring done):**
- Scale: this is a 1379-fn test app. A real Flutter app (100k+ fns) may surface
  *other* volatile entry kinds (more native/FFI entries, address-bearing
  `kImmediate`s). Re-run the harness on a real app; if identical-source link <
  ~100%, re-instrument with `SANKOFA_OP_DEBUG` and stabilize the next kind. The
  tooling + method are now in place.
- This measures HASH MATCHING (→ small patches). On-device *execution* of the
  patch (load patch-on-base, run changed code via the β.3 interpreter) is
  separate = Tasks 6/7, still pending but already proven as a mechanism.

**Revised critical path:** (1) re-validate the link at real-app scale, stabilize
any further volatile entry kinds; (2) Tasks 6/7 — the 12 engine patches +
`Dart_CreateIsolateGroupWithBaseSnapshot` + on-device round-trip (the actual
remaining blocker for shipping); (3) DD only later, as a cascade optimizer for
hot leaves (now clearly a *nice-to-have*: a 1-leaf change already links at
99.6% without it). `compute_dd_slot_mapping` + the alignment consumer drop down
the list.
