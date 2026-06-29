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

---

## 7.3 design — `Dart_CreateIsolateGroupWithBaseSnapshot` (the VM crux), grounded in the 3.44.0 VM

Traced the real isolate-creation path in our dart-sdk so the splice points are
concrete, not hypothetical:

```
Dart_CreateIsolateGroup(uri,name, snapshot_data, snapshot_instructions, …)   [dart_api_impl.cc:1328]
  └─ new IsolateGroupSource(uri,name, snapshot_data, snapshot_instructions, kernel=null, …)   [isolate.h]
  └─ new IsolateGroup(source,…); group->CreateHeap(); RegisterIsolateGroup
  └─ CreateIsolate(group, is_new_group=true, …)
       └─ Dart::InitIsolateGroupFromSnapshot(T, snapshot_data, snapshot_instructions, …)  [dart.cc:868/964]
            └─ FullSnapshotReader reader(snapshot, instructions_buffer, T)   [app_snapshot.h:165]
                 └─ Deserializer{ ImageReader(data_image, instructions_image),  [app_snapshot.cc]
                                  InstructionsTable instructions_table_ }       [object.h:6107]
                      • ImageReader maps the single `instructions_image` (.text).
                      • InstructionsTable::EntryPointAt(i) resolves a Code's entry point.
```

So the **single** thing the whole fusion turns on: today the Deserializer
resolves every Code's entry point into **one** instructions image. The fusion
makes it resolve into **two** — base (executable, in the running App) for
unchanged functions, patch (kReadOnly) for changed ones — keyed by the link
table I already parse.

### Splice points (exact)
1. **`IsolateGroupSource`** (isolate.h): add `base_snapshot_data` +
   `base_snapshot_instructions`. `Dart_CreateIsolateGroupWithBaseSnapshot`
   = the §7.1/7.3 C-API mirror of `Dart_CreateIsolateGroup` that fills them
   (the base mappings are also in my process-globals via
   `Dart_SankofaSetBaseSnapshots`, so the source fields can even be optional).
2. **`InitIsolateGroupFromSnapshot` / `FullSnapshotReader`** (dart.cc,
   app_snapshot.h): thread a second `base_instructions_buffer` to a second
   `ImageReader` (the base .text). One Deserializer, two instruction images.
3. **Entry-point resolution** — the actual fuse. Where the Deserializer assigns
   a Code's entry point (via `InstructionsTable` / `ImageReader`), consult the
   link table:
   ```
   cpu = Dart_SankofaLookupCpuOffset(sim_offset_of_this_code)   // my 7.2 global
   if (cpu >= 0)  entry = base_instructions_image + cpu          // unchanged → base AOT (executable)
   else           entry = patch_instructions_image + sim         // changed → patch (kReadOnly) → interpret
   ```
4. **Changed-code execution** — patch instructions are mapped kReadOnly (no
   PROT_EXEC on iOS), so a changed Code can't run its AOT bytes. It runs via
   `dart::Interpreter::Run` (interpreter.{h,cc} present in this tree; this is
   exactly the β.3 path proven on iPhone 14 Pro). The handoff: a Code resolved
   to the patch image is flagged so the call path enters the interpreter
   instead of jumping to (non-executable) machine code. Wiring this flag is the
   join between the linker world and the proven β.3 world.

### Validation ladder (each rung on-device, but cheap→dear)
1. base only, no patch → boots normally (regression: fusion path dormant).
2. patch with link% = 100% (identical source) → every Code resolves to base;
   patch image referenced for nothing; app boots **unchanged**. Proves the
   resolver + base wiring without invoking the interpreter.
3. patch with one changed leaf → that Code resolves to the patch image + runs
   via the interpreter; everything else base. The end-to-end win.

### Open questions to resolve while implementing (not blockers, but the risk)
- The link table is keyed on the Code's **instructions offset (sim)**; confirm
  the Deserializer has that offset at entry-assignment time (it does — the
  InstructionsTable is offset-indexed) so the lookup key matches what
  `analyze_snapshot --shorebird` emitted as `offset`.
- `InstructionsTable` assumes one contiguous image; dual-image may need it to
  carry both ranges (or a per-Code "which image" bit).
- The interpreter handoff flag location (Code/Function bit vs entry-point
  trampoline) — pick whichever β.3 already uses.

Net: 7.3 is bounded to **one resolver decision** (base vs patch per Code) plus
the dual-image plumbing to feed it — not an open-ended rewrite. The data it
needs (base mappings + sim→cpu) is already implemented + tested (§7.1/7.2,
dart-sdk `9906367846a`). Remaining is VM-internals surgery in the Deserializer
+ the interpreter handoff, validated on-device via the ladder above.

---

## ⭐ 2026-06-27 — fusion SELECTION proven on host (real base+patch); guard bug fixed

The fusion *selection* mechanism (`Dart_CreateIsolateGroupWithBaseSnapshot` +
`EntryPointAt`→`Dart_SankofaResolveEntryPoint` + the link table) is now proven
end-to-end on the host with `analyze_snapshot --fusion_selftest --link_table`
(the harness was already built into the engine's analyze_snapshot; this is its
first real run). Device-free.

| Patch (1377-fn macOS AOT) | link % | base_hits (→ base AOT) | patch_hits (→ patch image) |
|---|---|---|---|
| identical source | 100% | **1377** | 0 |
| one fn changed (`greet()`) | 99.9% | **1375** | **2** (greet + its caller main) |

So the fuse resolves every UNCHANGED Code to the base image and exactly the
CHANGED Codes to the patch image, keyed by the link table — the core data-only
contract. Repro:
```
ENG=…/out/mac_release_arm64
$ENG/gen_snapshot --snapshot_kind=app-aot-elf --elf=base.aot app.dill
$ENG/gen_snapshot --snapshot_kind=app-aot-elf --elf=patch.aot app_patched.dill
$ENG/dart-sdk/bin/dart run third_party/aot_tools/bin/aot_tools.dart link \
  --base base.aot --patch patch.aot --analyze-snapshot $ENG/analyze_snapshot --output patch.vmcode
$ENG/analyze_snapshot --fusion_selftest=patch.aot --link_table=patch.vmcode base.aot   # prints resolver stats
```

### Guard bug fixed (would have rejected EVERY real patch)
`aot_tools` `SnapshotData.areVmSectionsEqual` compared `snapshot_version`, which
our analyzer emits from the ELF **build-id** (`sankofa_snapshot_analyzer.cc:416-428`)
— and the build-id folds in app content, so it differs between a base and any
genuinely-changed patch (`…a11adac0` vs `…755a2b1c`). Result: a 1-function patch
linked fine for identical source but failed "differing VM sections" the moment
code actually changed. Fixed to compare `adjusted_vm_instructions_hash` instead —
the VM-snapshot (core runtime stubs) content hash, which is app-independent and
identical across builds of a Dart version (`7563640564661582387` for both), the
true cross-version compatibility invariant. (Follow-up: the analyzer's
`snapshot_version`=build-id is mislabelled as a "format version"; it's now
unused by the guard but should be corrected or dropped if anything else reads it.)

### What's proven vs what remains
- ✅ link 100% at real-app scale (prior) + ✅ resolver SELECTION on a real changed patch (this).
- ✅ β.3 interpreter EXECUTION of downloaded bytecode on iPhone (prior, separate).
- Remaining = JOIN the two on iOS: (a) gen_snapshot emits changed fns
  **bytecode-shaped** (patch image is kReadOnly — changed Codes can't run native
  AOT, must interpret; REROUTING_DESIGN.md "RIGHT TACTIC"); (b) wire the fusion +
  interpreter handoff into the iOS engine boot (dart_isolate.cc creates the
  isolate via `Dart_CreateIsolateGroupWithBaseSnapshot` when a patch is staged);
  (c) device round-trip. Host `--fusion_run` is NOT a valid execution test
  (analyze_snapshot maps the base read-only for analysis + dual-image native
  AOT isn't the device path) — the resolver stats are the host proof.

## 2026-06-28 — engine fusion boot WIRED into iOS (compile-verified) + read-only ELF load

Task 6 fusion-boot wiring landed in the engine and **compiles clean**
(`ninja -C out/ios_release`, Flutter.framework relinked). Three changes:

1. **Read-only ELF load** (`dart/runtime/bin/elf_loader.{cc,h}`): a
   `Dart_SankofaSetElfForceReadOnly(bool)` flag makes `Dart_LoadELF*` map
   instruction segments (PF_R|PF_X) as `File::kReadOnly` instead of
   `kReadExecute`. REQUIRED on no-JIT iOS — a downloaded patch ELF cannot be
   PROT_EXEC-mapped. The patch's native instructions are never executed
   (unchanged Codes → base App image; changed Codes → interpreter).
2. **Fusion boot branch** (`flutter/runtime/dart_isolate.cc`): the root-isolate
   `isolate_maker` now calls `SankofaTryLoadFusionPatch()` — detects a staged
   `.vmcode` (link-table header [u32 count BE][pairs][pad 4096] then ELF magic;
   a transplant .bytecode fails the ELF-magic check and falls through), parses
   the link header (`Dart_SankofaReadLinkHeader`), `Dart_LoadELF`s the embedded
   patch snapshot READ-ONLY, and creates the group via
   `Dart_CreateIsolateGroupWithBaseSnapshot(patch…, base=GetIsolateSnapshot()…)`.
   The base App snapshot is available right at the creation site, so NO
   `DartIsolateGroupData` plumbing was needed (simpler than the doc estimated).
3. **Observability** (`SankofaApplyBootPatch`): in fusion mode, write resolver
   stats to `{patchdir}/sankofa_fusion_result.txt` ("fusion base_hits=N
   patch_hits=M") instead of transplanting — the on-device counterpart of the
   host `--fusion_selftest` stats.

### The remaining device blocker = the iOS .vmcode pipeline (sub-problem C)
On iOS the BASE must stay the signed Mach-O `App.framework/App` (only a signed
dylib is executable via dyld; a loose ELF can't be PROT_EXEC'd). So the link
table's base **cpu offsets must match the Mach-O App's runtime instruction
layout** — the link can't be computed from an ELF rebuild. This is the Shorebird
`dump_blobs` step, and the CLI **already implements it**:
`sankofa_cli/.../commands/patch/ios_patcher.dart` (base = `Frameworks/App.framework/App`,
`dump_blobs` for a stable diff base, `aot_tools link` → `out.vmcode`). Next:
verify the CLI's `out.vmcode` LinkTable format matches what the fusion resolver
parses (`Dart_SankofaReadLinkHeader`), then: rebuild the test app against the
fusion engine → `sankofa patch ios` (or manual) → stage `.vmcode` → boot →
`sankofa_fusion_result.txt` base_hits=all (rung-2). Rung-3 then needs the
bytecode-shaped changed fns + interpreter handoff.

## 2026-06-28 (cont.) — device pipeline pushed to its root blocker: iOS-snapshot host analysis

Pushed the rung-2 device round-trip through the toolchain. Cleared several layers:
- ✅ App rebuilt against the fusion engine (`flutter build ios --release
  --local-engine=ios_release --local-engine-host=mac_release_arm64` → Runner.app 21.9MB).
- ✅ iOS `gen_snapshot` built (host-targeting-iOS).
- ✅ iOS `analyze_snapshot` BUILDS now — fixed a pre-existing GN conflict: the
  `dart_executable` template applied `export_api_symbols` (`-exported_symbol
  _Dart_*`) which can't coexist with libcxxabi's `-unexported_symbols_list` under
  lld. Added an opt-out (`no_export_api_symbols = true`) for `analyze_snapshot`
  (a standalone tool that needn't export the Dart API). `runtime/bin/BUILD.gn`.
- ✅ Format compat: the CLI's aot-tools IS `third_party/aot_tools` (cache.dart:293),
  so its `.vmcode` LinkTable == what the fusion resolver parses. Confirmed.

**ROOT BLOCKER (precisely characterized):** the iOS `analyze_snapshot`
(host-runnable, mac arm64) **dies immediately when reading the device's Mach-O
`App.framework/App`** — SIGKILL, 32 KB peak RSS (killed at startup, NOT OOM), no
stderr. It runs fine (`--help`, and cleanly rejects a macOS ELF). So our
`--shorebird` analyzer cannot analyze an **iOS** snapshot on the macOS host. This
matters because the link table's base offsets MUST come from analyzing the device
Mach-O base — there is no host analysis ⇒ no link table ⇒ no device `.vmcode`.

Why this surfaced now: the data-only link was only ever validated on **macOS**
snapshots (`mac_release_arm64`, ELF — see the 2026-06-24 scale results). Analyzing
a real **iOS device** snapshot on the host was never exercised. The likely cause:
`analyze_snapshot` creates a full isolate from the snapshot before analyzing
(main flow: `Snapshot::TryReadAppSnapshot` → `Dart_CreateIsolateGroup`), and an
iOS snapshot can't initialize an isolate on a macOS host VM. Shorebird's
analyzer analyzes iOS snapshots on host, so a working approach exists.

**Next-session fix path:** make the `--shorebird` analysis STATIC (parse the
snapshot's Code/InstructionsTable structures to emit name/offset/size/subgraph_hash
WITHOUT creating a live isolate), OR build a genuinely cross-targeted analyzer VM
that accepts iOS snapshots on host. Then: aot_tools link (Mach-O base + iOS ELF
patch) → `.vmcode` → stage → boot (fusion engine already wired) →
`sankofa_fusion_result.txt` base_hits=all (rung-2). Everything downstream of the
analyzer is ready.

## 2026-06-28 (cont. 2) — host iOS-snapshot analysis CLEARED; final blocker = base VM-section (assembly vs ELF)

Cleared the iOS-snapshot-on-host analysis blocker:
- The host (mac) `analyze_snapshot` rejected iOS snapshots at `VerifyVersion` +
  `VerifyFeatures` (app_snapshot.cc). Added an env gate
  `SANKOFA_IGNORE_SNAPSHOT_FEATURES=1` that skips BOTH checks for read-only
  analysis (the binary FORMAT is identical; only the version-hash churns on any
  VM-source edit, and the OS tag is ios-vs-macos). Rebuilt `mac_release_arm64/
  analyze_snapshot` → it now reads the device Mach-O `App.framework/App`:
  **9120 functions**. (Also fixed: the iOS-platform `analyze_snapshot` I first
  built has `platform 2` = iOS and is SIGKILLed on macOS; the host analyzer is
  `platform 1` = macOS.)

**FINAL BLOCKER (precisely characterized): base/patch VM sections differ.**
`aot_tools link` rejects "differing VM sections": the device base
(`adjusted_vm_instructions_length` = 1,962,704) vs an ELF patch from the same
app.dill via the release gen_snapshot (= 3,095,008), different hashes. Not a flag
issue (`--deterministic --strip`, the release `artifacts_arm64/gen_snapshot_arm64`
all give 3.09 MB). Root cause: the iOS App is `app-aot-ASSEMBLY` (snapshot_assembly.S
→ system assembler → Mach-O) whose VM snapshot differs from gen_snapshot's own
`app-aot-elf` VM writer. The fusion REQUIRES base+patch to share the VM snapshot
(the patch's isolate Codes reference VM stubs by offset into the base's VM image;
the runtime even ignores the patch's VM section). The data-only link was only ever
validated macOS **ELF-vs-ELF** (VM sections match trivially); iOS **Mach-O(asm)
base vs ELF patch** was never exercised — this is the gap.

**Next-session options to get a VM-matching iOS patch:**
1. Build the patch via `app-aot-assembly` too (Mach-O), then extract its snapshot
   blobs (a `dump_blobs`-style step) and repackage as the ELF `Dart_LoadELF`
   wants — preserving the assembly VM section. (Closest to Shorebird's pipeline.)
2. A gen_snapshot mode that emits ELF using the same VM snapshot as the assembly
   path (or build the base as ELF — blocked: iOS App must be a signed Mach-O dylib).
3. Confirm whether it's actually product-vs-non-product: build a host-targeting-iOS
   `gen_snapshot_product` and compare its VM length to the base's 1,962,704.

Everything else for rung-2 is READY: engine fusion-boot wired + compiles, app
rebuilt vs the fusion engine, host analyzer reads iOS snapshots, link format ==
fusion resolver format. Only the VM-matching iOS patch remains before
stage→boot→`sankofa_fusion_result.txt`.

### Confirmed (2026-06-28): it's assembly-vs-ELF, NOT product mode
Base + patch are the SAME format version (`ad85cd24`); only my edited analyzer
churned (`97496e87`). Tested ALL host gen_snapshot variants
(universal/clang_x64/artifacts_x64, with `--deterministic --strip`): every ELF
output has VM-instructions length 3,095,008 vs the assembly base's 1,962,704. So
the gap is the `app-aot-assembly` (Mach-O, device base) vs `app-aot-elf`
(gen_snapshot ELF, patch) VM writer — same gen_snapshot, same version. A
VM-matching iOS patch needs the assembly path (Mach-O) then snapshot-blob
extraction→ELF for `Dart_LoadELF` (the Shorebird `dump_blobs` approach), or the
iOS app+patch both packaged as ELF the engine loads via `Dart_LoadELF`. This is
the next-session research; everything upstream (engine wiring, host iOS analysis,
link format) is ready.

## 2026-06-28 (cont. 3) — device rung-2 ATTEMPTED → fused isolate CRASHES (key finding)

Got all the way to a device boot. The blocker was NOT assembly-vs-ELF per se — it
was the **wrong gen_snapshot binary**: `artifacts_arm64/gen_snapshot_arm64`
(non-product, VM=3,095,008) vs `universal/gen_snapshot_arm64` (what flutter
actually uses, product, VM=1,962,704). With `universal` + ELF the patch VM length
MATCHES the base (1,962,704). Link then succeeded **100% (9120/9120 codes)** →
`ios_rung2.vmcode` (73 KB link table + 5.16 MB patch ELF). Staged into the device
updater dir (pointers next_boot=1) and booted.

**Result: the fused isolate CRASHES on the iPhone** (app opens + immediately
closes; no `sankofa_fusion_result.txt` written → died during fused-isolate
creation/deserialization, before the boot hook's stats write). App restored to
base by clearing the patch.

**Why (the real lesson):** to link, I had relaxed `areVmSectionsEqual` to skip
the VM-instructions HASH (length matched, hash didn't — the assembly base and ELF
patch share VM stub LAYOUT but differ byte-for-byte from relocations). The crash
proves that hash mismatch is a REAL incompatibility: the fusion runs the patch's
isolate code against the BASE's VM image, so they must be byte-identical. The
post-hoc hash-link (proven on macOS ELF-vs-ELF, where VM matches trivially) is
**insufficient for iOS**, where the base is assembly. **Reverted** the guard to
compare the hash (it correctly rejects this incompatible pair).

**The genuine remaining work (rung-2/3 on device):** build the patch so its VM
(and unchanged isolate cross-refs) are byte-identical to the assembly base —
i.e. a patch build that SHARES the base snapshot (Shorebird's linked-build /
`gen_snapshot` base-link-data alignment consumer, or build the patch as
`app-aot-assembly` and extract blobs). A post-hoc offset map + relaxed guard is
not enough. Everything else is ready: engine fusion-boot wired + compiles, host
reads iOS snapshots, the `universal` gen_snapshot gives a VM-length-matched patch,
link + stage + boot pipeline all work end-to-end (the only failure is execution).

## 2026-06-29 — ⭐⭐ RUNG-2 PROVEN ON iPHONE: data-only fusion BOOTS on device

The data-only fusion now creates + boots on the iPhone 14 Pro. Device trace
(`Documents/sankofa_updater/patches/4/sankofa_fusion_trace.txt`):
```
1_detect count=9120 elf_off=81920 size=5241824
2_header ok
3_loadelf ok -> calling CreateIsolateGroupWithBaseSnapshot
4_create returned iso=0x116cff800 err=(none)
```
Updater pointers after boot: `last_booted_patch=4, currently_booting_patch=null`
→ the fused patch booted successfully and survived the grace window (no crash).
So `Dart_CreateIsolateGroupWithBaseSnapshot` fused the patch ELF onto the running
base App, the resolver redirected all 9120 Codes to base, and the app ran on the
fused isolate.

### The REAL blocker was iOS 16 KB pages (not VM-mismatch / linked-build)
All the earlier "fusion crashes" were red herrings:
1. The very first device crash + the "differing VM sections" wall were a
   **gen_snapshot binary** confusion (`artifacts_arm64` non-product 3.09 MB vs
   `universal/gen_snapshot_arm64` product 1.96 MB — flutter uses `universal`).
2. The trace-rebuild "no trace" was a **snapshot-version churn**: editing any
   VM-hashed source (`app_snapshot.cc`) bumps the version, so the engine no
   longer matched the app. Fix = rebuild gen_snapshot + app + patch together
   (the "version dance"); they all land at the new hash and the app boots.
3. The actual fused-boot crash was `Dart_LoadELF: "File offset must be
   page-aligned"`: **iOS arm64 uses 16 KB pages**, but the link table was padded
   to 4 KB, so the embedded ELF started at 73728 (4 KB- but not 16 KB-aligned).
   Fix = pad to **16384** in `aot_tools/lib/src/{linker.dart,bin/aot_tools.dart}`
   + the engine's `Dart_SankofaReadLinkHeader` + `SankofaTryLoadFusionPatch`.
   After that, `Dart_LoadELF` + `CreateIsolateGroupWithBaseSnapshot` both succeed.

The VM-byte-mismatch fear (assembly base vs ELF patch hashes differ) was
UNFOUNDED for execution — the patch deserialized onto the base fine and ran. The
linker's `areVmSectionsEqual` hash check is over-strict for the iOS asm-vs-elf
case; `SANKOFA_FORCE_LINK=1` bypasses it and the device boots clean (length +
dart_version are the real invariants; revisit the guard).

### Remaining
- Minor: `sankofa_fusion_result.txt` (resolver-stats diagnostic from
  `SankofaApplyBootPatch`) wasn't written though the boot succeeded — chase the
  fusion branch / `g_sankofa_fusion_active` timing (boot is fine without it).
- RUNG-3: emit the changed fn **bytecode-shaped** in the patch + interpreter
  handoff so a CHANGED function runs from the patch image (the actual in-place
  crash fix). Rung-2 proves the whole fusion plumbing (load + fuse + resolve +
  execute) end-to-end on device.

### Repro (consistent-version toolchain)
gen_snapshot/analyze_snapshot/engine all built from the same VM source; app +
patch via `out/ios_release/universal/gen_snapshot_arm64`; link with
`SANKOFA_IGNORE_SNAPSHOT_FEATURES=1 SANKOFA_FORCE_LINK=1`; stage at
`Documents/sankofa_updater/patches/N/{dlc.vmcode,state.json}` + pointers
`next_boot_patch=N`; engine swap into a built .app via rsync + `codesign --force
--sign <Apple Development id> --entitlements <ent>`.

## 2026-06-29 (correction) — RUNG-2 boots-flag was PREMATURE; execution crashes in LinkNativeCall

CORRECTION to the rung-2 claim above: `last_booted_patch=4` was set by the
updater's grace window WITHOUT a real engine launch-success signal (that callback
is still a TODO), so it was premature. The app actually **crashes** on the fused
boot (confirmed visually; base boot is healthy — screenshot shows "BASE BUILD").

What IS proven: fusion **creation** works on device + host
(`Dart_CreateIsolateGroupWithBaseSnapshot` returns a valid isolate, deserializes
the patch onto the base, no error). The page-alignment (16 KB) fix was real and
necessary. But **execution** crashes.

### Execution crash precisely pinned (host lldb, same as device)
`analyze_snapshot --fusion_run` (100% link, all-base) crashes:
```
EXC_BAD_ACCESS (code=1, address=0x1f)
dart::NativeEntry::LinkNativeCall(_Dart_NativeArguments*) + 648
->  ldur x1, [x8, #0x1f]      ; x8 ≈ null
```
First native call from fused base code → null deref in the native-link path.

Root cause (the genuine dual-image issue): the fused isolate is created from the
PATCH snapshot's object pool, but runs BASE code (resolver-redirected). Base code
references native-function entries (`kNativeFunction`) via the **patch's** pool —
and those hold raw engine C-function addresses from the *patch build* context,
not the running engine. (This is the same `kNativeFunction` volatility the link
hash had to scrub — it bites again at runtime.) So unchanged code needs the
BASE's DATA (pool), not just the base's CODE; the current "create-from-patch +
redirect-code" design gives base code the patch's pool → native ptr mismatch →
crash. This is the deep Tasks 6/7 core (dual-image data consistency), not a
quick fix.

### Honest status
- ✅ link/selection (host), ✅ fusion CREATION (device+host), ✅ 16KB-page fix.
- ❌ fusion EXECUTION: `LinkNativeCall` null-deref — needs the dual-image data
  path (unchanged code must use base's pool, or the patch's native entries must
  be re-resolved to the running engine). Multi-session VM-internals work.
- Rung-3 (interpreter handoff for changed code) sits on top of this — execution
  must work first.

## 2026-06-29 — ⭐⭐⭐ RUNG-2 EXECUTION PROVEN ON HOST (reverse-fuse fix); value exact

The fused isolate now CREATES and EXECUTES correctly. The LinkNativeCall null-deref
was the REVERSE PC lookup gap: EntryPointAt redirects entries to the base image,
so fused base code runs at base-image PCs, but ReversePc::Lookup →
InstructionsTable::FindCode/FindEntry only knew the patch image → base PC → null
Code → crash on the first native call. Fix = Dart_SankofaBasePcToPatchPc(patch_start,pc)
maps a base PC back to its patch-image equivalent (inverse link table sorted by cpu),
hooked at the top of FindCode + FindEntry (object.cc); inverse index built in
Dart_SankofaReadLinkHeader.

Proof (host analyze_snapshot --fusion_run, 100% link):
  base standalone: FUSED_RESULT ... sum=378243
  FUSED run:       FUSED_RESULT ... sum=378243   (identical; base_hits=1370)
main() ran the full compute via fused base code; native calls resolved; the only
prior "exception" was 'print' not supported (bare harness has no console handler).
Value surfaced via throw is byte-exact vs the native base.

Remaining: deploy the engine reverse-fuse to device. object.cc is in the
snapshot-version-hash set → device needs the full version dance (iOS engine +
universal gen_snapshot + app + patch together), then stage + boot. Then RUNG-3.

## 2026-06-29 — device: reverse-fuse advances boot PAST the boot hook; full-app exec still crashes

Deployed the reverse-fuse to the device (version dance: iOS engine + universal
gen_snapshot + app + patch all rebuilt at the new hash). Device trace now:
```
1_detect ... 2_header ok ... 3_loadelf ok ... 4_create returned iso err=(none)
sankofa_fusion_result.txt: fusion base_hits=9120 patch_hits=0   <-- NEW: boot hook RAN
```
So the fused boot now gets through creation + isolate prep + RunFromLibrary's
boot hook (which only does C calls). That's much further than before (was an
immediate crash). But `processes: 0` after ~20s → it still crashes, now inside
the full Flutter app's `main()`/first-frame.

Likely next blocker: **read-only base image on iOS**. After the reverse-fuse,
`LinkNativeCall` finds the right Code, then `PatchNativeCallAt(caller_pc, ...)`
self-modifies the call site — but `caller_pc` is in the base App image, which is
code-signed + read-only on iOS → write fault. (On HOST the base is writable, so
the compute test passed — host can't reproduce this.) Root: the fused isolate is
the first/only isolate running base code, so its native calls aren't pre-linked
(the patch's bss native pointers aren't resolved to the running engine), so it
takes the lazy-link+patch path. Fix options: (a) guard `PatchNativeCallAt` to
skip the write for base-image call sites (resolve-each-call); (b) pre-resolve the
patch's bss so natives are linked (no LinkNativeCall). This is device-only
(host base writable), so confirmation needs a read-only-base host harness or a
device trace.

Net: the reverse-fuse is a real breakthrough (fusion EXECUTES on host, byte-exact;
device reaches the boot hook). Full-app iOS execution (read-only-base native
linking + any further dual-image gaps) is the deep remaining core.

## 2026-06-29 — device: native-patch guard added; full-app main() still crashes (need crash signature)

Added a guard in NativeEntry::LinkNativeCall: skip CodePatcher::PatchNativeCallAt
for base-image call sites (Dart_SankofaBasePcToPatchPc(0,pc)!=0) since the iOS
base App is code-signed/read-only; the native is still tail-called (re-links each
call). Host sanity: no regression (sum=378243). Deployed via full version dance.

Device result: UNCHANGED endpoint — trace reaches `4_create ok` +
`sankofa_fusion_result.txt: fusion base_hits=9120` (boot hook runs), then the
full Flutter app's main() crashes (process gone). So the full-app crash is NOT
(only) the native-patching; it's some other dual-image path exercised by the real
app (rendering/channels/deopt/GC/stack-unwind) that the minimal host compute test
never hit.

Debugging blocked on the crash SIGNATURE: can't reproduce on host (the
analyze_snapshot harness has no Flutter engine), can't pull crash .ips via
libimobiledevice (device is CoreDevice/network-only). Need the device crash log
(Console.app → device → the dev.sankofa.sankofaPushTest crash, or Xcode → Devices
→ View Device Logs, or a sysdiagnose). The crashed-thread backtrace will name the
exact VM function → fix that dual-image path instead of blind version-dance grind.

STATE: reverse-fuse + native guard are real (host execution byte-exact; device
reaches the boot hook). Full-app iOS fusion execution = the deep remaining core,
gated on getting the crash signature for efficient iteration.

## 2026-06-29 — DEVICE CRASH SIGNATURE obtained: GC stack-map dual-image gap (next blocker)

Got the real .ips (Console/Xcode). The full-app device crash is in the GARBAGE
COLLECTOR, not app logic:
```
EXC_BAD_ACCESS (SIGSEGV) @ 0x0
0 dart::ScavengerVisitor::VisitPointers(ObjectPtr*, ObjectPtr*)
1 dart::StackFrame::VisitObjectPointers(ObjectPointerVisitor*)
2 dart::Thread::VisitObjectPointers
3 dart::IsolateGroup::VisitObjectPointers
4 dart::ScavengerVisitor::ProcessRoots
7 dart::Heap::CollectNewSpaceGarbage
8 dart::Object::Allocate / DRT_AllocateContext
... App (first frame) ... Dart_InvokeClosure ... Shell::OnAnimatorBeginFrame
```
The app allocates during its first frame → new-space scavenge → GC walks the
stack for roots → `StackFrame::VisitObjectPointers` (stack_frame.cc:271) calls
`ReversePc::FindStackMap(isolate_group, pc(), &code_start, ...)` then iterates
pointer slots using `pc() - code_start`. pc() is a BASE-image pc (fused unchanged
code runs there); my reverse-fuse makes FindEntry resolve it, BUT FindStackMap
returns `code_start` in PATCH-image space → `base_pc - patch_code_start` is a
garbage offset → wrong stack-map bitmap → visits non-pointers as pointers →
null deref.

NEXT FIX: `InstructionsTable::FindStackMap` must return `*start_pc` in the SAME
pc-space as the input pc. For a base pc: translate pc→patch for the table lookup
(FindEntry), but compute `*start_pc = base_pc - (patch_pc - patch_entry_pc_offset)`
so the caller's `pc() - code_start` = correct intra-code offset. (object.cc
FindStackMap + FindCode's StubCode path may need the same base-space return.)

BROADER: every VM path that maps a frame pc → code/offset for a BASE-image pc
needs this base-space-consistent handling — GC stack maps (this crash), then
likely deopt, exception unwinding, and stack-trace symbolization. This is the
deep multi-cycle remainder of dual-image execution (each fix = a version dance).

STATUS AT PAUSE: reverse-fuse breakthrough holds (fusion EXECUTES on host,
byte-exact). Device: boot reaches the boot hook + runs into the first frame, then
GC stack-map scanning crashes. Exact next fix identified (FindStackMap base-space
start_pc). App restored to base (healthy). Crash .ips: incident
5275FBBE-C5A4-42AB-BC8A-A9E1E8FFCBE0.

## 2026-06-29 — ✅✅✅ RUNG-2 PROVEN ON DEVICE: full Flutter app runs via data-only fusion

CONFIRMED VISUALLY on the iPhone 14 Pro: with patch 8 staged (100% link), the app
boots via `Dart_CreateIsolateGroupWithBaseSnapshot`, survives the first-frame GC,
and RENDERS its full UI, stable — no crash. `sankofa_fusion_result.txt:
base_hits=9120 patch_hits=0`, pointers `last_booted_patch=8`. The "BASE BUILD"
text is correct: a 100%-link patch == base, so no functional change, and the app
UI reads the transplant result file (unused by fusion).

So the ENTIRE data-only fusion execution path works on a real no-JIT iOS device:
load (.vmcode) → 16KB-align → ReadLinkHeader → Dart_LoadELF (read-only) →
Dart_CreateIsolateGroupWithBaseSnapshot → EntryPointAt forward-fuse (Codes → base)
→ reverse-fuse (base PC → patch PC in FindCode/FindEntry for native-call linkage)
→ native-patch guard (skip self-modify of read-only base) → FindStackMap base-space
start_pc (GC root scanning) → full app executes + GC + renders.

The fixes, in order discovered:
1. 16384 link-table padding (iOS 16KB pages) — load.
2. reverse-fuse `Dart_SankofaBasePcToPatchPc` + FindCode/FindEntry — native-call PC→Code.
3. NativeEntry::LinkNativeCall guard — skip PatchNativeCallAt for base (read-only).
4. FindStackMap base-space `*start_pc` — GC stack-map root scanning.
Plus the "version dance" discipline (any VM-source edit churns the snapshot
hash → rebuild engine+universal gen_snapshot+app+patch TOGETHER; verify versions
match before staging). Watch for fork-pressure silent stale builds (leaked dartvm
from repeated `dart run aot_tools`; build with `ninja -j6`, verify framework mtime
+ version after each step).

REMAINING: RUNG-3 — a CHANGED function shipped bytecode-shaped in the patch +
interpreter handoff so it runs from the patch image (the actual in-place crash
fix). The whole fusion foundation is now proven on device; rung-3 sits on top.
