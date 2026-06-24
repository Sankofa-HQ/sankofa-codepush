# Tasks 6/7 — engine fusion (the real remaining blocker for iOS code-push)

Status (2026-06-24): the **link** is solved + scale-validated (see
`IOS_DATA_ONLY_PORT_PLAN.md` — 100% on a 17k-fn real Flutter app from a
deterministic analyzer hash). What remains to actually ship iOS code-push is
the **device-side fusion**: load a patch `.vmcode` on top of the running base
App snapshot and execute changed code (via the already-proven β.3 interpreter
on no-JIT iOS). This doc is the grounded contract for that, extracted from the
real engine call sites in the 12 patches — no guessing.

## Version reality (decides how Task 6 is done)

| Thing | Version |
|---|---|
| Our engine (built, on disk) | **3.44.0** / engine `0b7370de` |
| Extracted engine patches (`codepush-extraction/flutter/patches/*`) | **3.35.7** (0012 = "squash on top of 3.35.7") |
| Shorebird's cached flutter fork (`~/.shorebird/bin/cache/flutter`) | **3.41.6** (tag v1.6.92) |
| `shorebirdtech/dart-sdk` (the VM impls) | **PRIVATE / 404** — unobtainable |

So: (a) the engine C++ patches are 3.35.7 → a cross-version apply onto 3.44.0;
the cached 3.41.6 fork is closer but its **engine** repo is squashed to one
commit (per `EXTRACTION_BLOCKED.md`), so re-deriving clean per-file patches at
3.41.6 isn't free either. (b) The **Dart-VM implementations are unobtainable**
— Task 7 is genuine reverse-engineering from the call-site contract below
(founder decision 2026-06-01). The contract IS fully recoverable from the
engine `+` lines; that's what makes this tractable.

## The 12 patches, categorized

| Patch | What | Bucket |
|---|---|---|
| 0001 | 2-pass DD release build | **DD — deferred** (now nice-to-have; 1-leaf change already links 99.6%) |
| 0002 | Rust updater → GN/Ninja | build wiring (have updater in `sankofa-codepush/updater`) |
| 0003 | C++ interface onto updater (13 files) | engine↔updater glue |
| 0004 | split shorebird C API consumption | engine glue |
| 0005 | patch_verification_mode | signing/verify (have v2 envelopes) |
| **0006** | load TWO patches into runtime (10 files) | **fusion core** — `ReadLinkHeader`+`Dart_LoadELF` |
| 0007 | works without env (19 files) | link-info emitters = **Task 2 (done in analyzer)** |
| **0008** | `Shorebird_SetBaseSnapshots` for iOS (6 files) | **fusion core** |
| **0009** | crash-after-patch on iOS (2 files) | **fusion core** (stability) |
| **0010** | new CreateGroupIsolate API (6 files) | **fusion core** — `Dart_CreateIsolateGroupWithBaseSnapshot` |
| **0011** | FlutterEngineGroup breaks patching | **fusion core** (multi-engine) |
| 0012 | squash on 3.35.7 (64 files, 168 KB) | the bulk baseline |

Task 6 = port the **fusion-core** set (0006/0008/0009/0010/0011 + the glue from
0003/0004) onto 3.44.0. Task 7 = implement the 3 VM functions they call.

## Task 7 — the Dart-VM C-API contract (reverse-engineered from call sites)

These are the ONLY VM symbols the engine patches call that don't exist in
vanilla Dart. Names will be `Sankofa_*` in our fork (engine port renames the
call sites to match). All three confirmed verbatim from `+` lines in the
patches.

### 7.1 `Sankofa_SetBaseSnapshots` — stash the base App snapshot (SIMPLE)
```c
// engine call (patch 0008, at engine/Dart init with the base App.framework snapshot):
Shorebird_SetBaseSnapshots(isolate_snapshot->GetDataMapping(),
                           isolate_snapshot->GetInstructionsMapping(),
                           vm_snapshot->GetDataMapping(),
                           vm_snapshot->GetInstructionsMapping());
```
Signature: `void Sankofa_SetBaseSnapshots(const uint8_t* isolate_data, const
uint8_t* isolate_instr, const uint8_t* vm_data, const uint8_t* vm_instr)`.
Impl: store the 4 pointers in VM-global state (read later by the isolate-fusion
path). Trivial setter. Note the linker invariant: the VM snapshot is identical
across builds of a Dart version, so vm_data/vm_instr are effectively a
consistency check (the patch loader even ignores the patch's VM section).

### 7.2 `Sankofa_ReadLinkHeader` — parse the .vmcode LinkTable header (BOUNDED)
```c
// engine call (patches 0006/0012, before Dart_LoadELF of a patch):
int elf_file_offset = Shorebird_ReadLinkHeader(elf_mapping->GetMapping(),
                                               elf_mapping->GetSize());
... Dart_LoadELF(patch_path, elf_file_offset, &error, ...);
```
Signature: `intptr_t Sankofa_ReadLinkHeader(const void* mapping, intptr_t size)`.
Reads the LinkTable prefix WE define + emit (CODEPUSH_SPEC §4,
`aot_tools/lib/src/linker.dart::LinkTable.toBytes`):
```
[ count : uint32 BE ]
[ (sim_offset uint32 BE, cpu_offset uint32 BE) × count ]
[ zero pad → next 4096 boundary ]   ← returned value = this padded size
```
Impl: read count, validate `8 + 8*count <= size`, stash the sim→cpu map in
VM-global state (used during patch relocation), return the 4096-aligned header
size (where the real ELF begins). **Format is fully ours → unit-testable
against `LinkTable.toBytes()` output without any device.** This is the cleanest
first VM function to land.

### 7.3 `Dart_CreateIsolateGroupWithBaseSnapshot` — the fusion (THE CRUX)
```c
// engine call (patch 0010, only when SHOREBIRD_USE_INTERPRETER && base present):
Dart_CreateIsolateGroupWithBaseSnapshot(
    advisory_script_uri, advisory_script_entrypoint,
    patch_isolate_snapshot_data,  patch_isolate_snapshot_instructions,
    base_isolate_snapshot_data,   base_isolate_snapshot_instructions,
    flags, isolate_group_data, isolate_data, error);
```
= standard `Dart_CreateIsolateGroup` + base isolate data/instr. The VM creates
the group from the PATCH snapshot but resolves unchanged code to the BASE
instructions via the sim→cpu link table (7.2); changed code runs through the
interpreter (no PROT_EXEC on iOS). This is the deep VM-internals piece —
isolate-group creation, dual-snapshot reader, relocation using the link table.
Multi-week; needs the VM snapshot reader internals + the interpreter glue
(β.3, already proven as an execution model on iPhone 14 Pro).

Engine plumbing it rides on (patch 0010, already specified): `DartIsolateGroupData`
gains a `base_snapshot_` member + `GetBaseSnapshot()`; the shell passes
`GetBaseIsolateSnapshot()` through `CreateIsolateGroup`.

## Device flow (end to end)
1. Engine init → `Sankofa_SetBaseSnapshots(base iso+vm data/instr)`.
2. Patch present → `off = Sankofa_ReadLinkHeader(vmcode, size)` (stash sim→cpu)
   → `Dart_LoadELF(vmcode, off)` → patch isolate data/instr.
3. `Dart_CreateIsolateGroupWithBaseSnapshot(…, patch…, base…)` → fused isolate;
   unchanged = base AOT, changed = interpreter via link table.
4. First frame OK → `sankofa_report_launch_success` (Task 8, updater grace
   window already shipped) commits the patch.

## Recommended order + validation gates
1. **7.2 `Sankofa_ReadLinkHeader`** — implement in dart-sdk + a host unit test
   feeding `LinkTable.toBytes()`. Compiles + validates with NO device. ← start here.
2. **7.1 `Sankofa_SetBaseSnapshots`** — setter + VM-global storage (shared with 7.2's link table). Compiles; validated via 7.3.
3. **Task 6 fusion-core port** (0006/0008/0009/0010/0011 + glue) onto 3.44.0.
   Decide first: cross-version-apply the 3.35.7 patches vs hand-port using them
   as a spec (likely hand-port — 3.35.7→3.44.0 shell/runtime drift is large).
4. **7.3 `Dart_CreateIsolateGroupWithBaseSnapshot`** — the VM fusion. Validate
   incrementally: identical-source patch (link 100% → patch is a no-op → must
   boot unchanged), then a 1-function change on iPhone (the β.3-proven path).
5. Engine rebuild (iOS device config) + on-device round-trip = the finish line.

Reuse: β.3 interpreter execution (proven, `project_codepush_beta3_cross_platform`),
the updater grace-window (`lifecycle.rs`), v2 signed envelopes, the
`KnownEngine` registry + CDN. The fusion is the one genuinely-new VM piece.
