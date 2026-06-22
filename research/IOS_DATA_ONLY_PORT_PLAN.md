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
