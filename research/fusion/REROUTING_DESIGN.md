# Sankofa CodePush iOS — arbitrary-logic rerouting design (DD layer)

Status as of 2026-06-25. This is the engineering plan for the LAST architectural
piece of arbitrary-logic (crash-fix / large-update) iOS code-push. Everything
upstream of it is proven device-free in our own engine.

## ⚖️ DECISION LOCKED (2026-06-25): FUSION + DD is the architecture

We evaluated two architectures and committed to one. **Do not re-litigate.**

- **Override-in-place** (transplant a changed function's bytecode onto the live
  base function): PROVED the *execution primitive* (a live AOT function runs new
  downloaded bytecode via the interpreter, no JIT). But it is the WRONG
  architecture for rerouting: it mutates the running base isolate, whose linkage
  is baked, so it must re-solve rerouting for EVERY call kind at runtime —
  baked static calls (need DD), dispatch-table calls (baked), AND switchable/
  monomorphic instance calls (TESTED: forcing switchable via
  SANKOFA_NO_TABLE_DISPATCH made the call switchable but it STILL didn't reroute,
  because a monomorphic instance call enters at the *monomorphic* entry point and
  the InterpretCall stub installed by AttachBytecode isn't set up for that entry
  — see `SetInstructionsSafe`). Re-building all of that at runtime is MORE work
  than the proven path, with more correctness surface.
- **Fusion** (Shorebird's proven production model): create the isolate from the
  PATCH snapshot, so its dispatch table, monomorphic entry points, and call sites
  are internally consistent *by construction* — rerouting is correct for free for
  every call kind. The fuse (`Dart_SankofaResolveEntryPoint`, proven
  base_hits=1375) redirects UNCHANGED functions' instructions to the base image
  so they aren't re-shipped. The only residual rerouting gap is
  unchanged(base-instruction)-calls-changed, which is exactly what DD fixes
  (route those calls through an indirect slot).

**Therefore the path is: FUSION + hybrid snapshot (changed fns → bytecode in the
patch snapshot) + DD (for unchanged→changed call edges) + the proven fuse.**
The override-in-place transplant primitive is retained as the proof that the
interpreter runs downloaded code no-JIT (it's the same Interpreter::Run the
fusion model uses for changed functions), but it is NOT the production patch path.

Remaining build (multi-week, deep VM/serializer work):
1. Hybrid snapshot: gen_snapshot emits changed fns as bytecode (Code=InterpretCall
   stub, correct entry kinds) AND the app-snapshot serializer/deserializer carry
   that bytecode (today `app_snapshot.cc` has NO bytecode handling — the core
   gap). Build-time emission gives correct monomorphic/unchecked entries for free
   (unlike runtime transplant).
2. DD consumer for unchanged→changed edges (producer done): see §B below.
3. CLI (2-pass build + diff) → engine-shell (load patch snapshot + fuse + create
   fused isolate, per patches 0006/0010) → iOS rebuild → on-device round-trip.

## What is already PROVEN (device-free, committed)

1. **Unchanged code → base AOT** (the "fuse"): `analyze_snapshot --fusion_selftest`
   → base_hits=1375 / patch_hits=3. (sankofa-dart-sdk `803b93e60e0`)
2. **No-JIT downloaded bytecode execution**: a 1.4 KB `dart2bytecode` module runs
   via `Interpreter::Run` on `dartaotruntime_product` (precompiled, no JIT).
   (sankofa-codepush `62165a0`, `research/fusion/prove_nojit_bytecode.sh`)
3. **⭐ Arbitrary-logic override-in-place primitive**: `Dart_SankofaTransplantBytecode`
   (`Function::AttachBytecode` = store bytecode + `SetInstructions(InterpretCall stub)`)
   flips a LIVE AOT function to interpreted downloaded bytecode. compute() went
   from native 'BASE' to interpreted 'PATCH-CRASH-FIXED', no JIT. This is a real
   function-body replacement (the crash-fix capability), not a text/color overlay.
   (sankofa-dart-sdk `40d3f2518aa`, harness `research/fusion/override_in_place/`)

## The problem this doc solves: REROUTING

A transplant flips the function, but existing callers must actually REACH the new
body. Measured with three probes after transplanting a function (committed test
`research/fusion/override_in_place/`, dart-sdk `946c4cdc428`):

| Call kind                              | After transplant      | Reroutes? |
|----------------------------------------|-----------------------|-----------|
| Fresh dispatch (Dart_Invoke, re-resolved) | PATCH-CRASH-FIXED  | ✅ |
| Baked direct static call               | caller-> BASE         | ❌ |
| Virtual dispatch-table call (build())  | render-> BASE-UI      | ❌ |

Root cause: AOT bakes call targets at snapshot-build time.
- A **static** call is a `Code::kPcRelativeCall` to the callee's entry, baked into
  the caller's instructions (`flow_graph_compiler.cc:956`, `GenerateStaticDartCall`).
- A **virtual** call indexes a flat `uword[]` dispatch table baked at snapshot time
  (`il.cc:5435`, `DispatchTableCallInstr::EmitNativeCode`) and jumps to the entry
  WITHOUT passing the Function the InterpretCall stub needs — so you can't just
  point a table slot at the stub.

On iOS the base code pages are r-x and unwritable without a JIT entitlement, so
detour/hot-patch of baked targets is impossible. **Indirection decided at
base-build time is the only option.** This is exactly why Shorebird built DD.

## Two rerouting mechanisms (compose for full coverage)

### A. Instance/virtual calls → switchable calls + IC flush (covers most Flutter)
Most Flutter patch points are virtual methods (build(), lifecycle, overrides).
`aot_call_specializer.cc:1223` converts an instance call to a `DispatchTableCall`
ONLY when `precompiler_->selector_map()->GetSelector(interface_target) != nullptr`.
If the selector map is empty, the call stays a **switchable instance call**
(monomorphic→megamorphic), which caches `(cid → entry)` and RE-RESOLVES on a miss.

Plan:
- Build the base app with dispatch-table generation disabled (skip
  `dispatch_table_generator_` at `precompiler.cc:488`, or force
  `SelectorMap::SelectorId` to kInvalid). Cost: instance calls slower (IC vs table
  index) — acceptable for patchability; measure.
- On transplant, **flush the switchable-call caches / ICData referencing the
  patched function** so the next call re-resolves to the function's current Code
  (the InterpretCall stub) → interpreter. (Hot-reload already has IC-reset
  machinery to model this; it's `#if !PRODUCT` so port the needed reset into a
  precompiled-runtime path.)
- Verify: re-run the virtual probe (`renderNew()`); expect PATCH-UI after flush.

### B. Static-direct calls → DD indirect static call table (Shorebird's DD)
For non-instance static calls, route through a base-resident indirect table:
- **Producer (DONE)**: `analyze_snapshot --compute_dd_table` builds the fan-in
  graph, selects highest-cascade functions within a byte budget, assigns slots,
  keyed by subgraph_hash. (codepush `eeefd9457d1`)
- **Remaining**:
  1. `gen_snapshot --print_dd_function_identity_to` — emit each function's
     identity + kernel_offset (so the slot map can bridge subgraph_hash↔kernel_offset).
  2. `analyze_snapshot --compute_dd_slot_mapping` — produce `kernel_offset → slot`.
  3. `gen_snapshot --dd_slot_mapping` + `FinalizeIndirectStaticCallTable` — at
     `GenerateStaticDartCall` (`flow_graph_compiler.cc:956`), for a DD-slotted
     callee emit `load func; indirect-call slot[i]` instead of the baked
     `kPcRelativeCall`. (Per-arch assembler work; the deepest piece.)
  4. Runtime: a base-resident `uword[] dd_table` + `Dart_SankofaUpdateDdSlot(i, entry)`;
     the patch repoints slots for changed functions → all callers reroute.

The 2-pass base build (from Shorebird engine patch 0001, flutter-tools side):
pass 1 emit identity + compute table + slot mapping; pass 2 gen_snapshot with
`--dd_slot_mapping` rewrites the call sites.

## Recommended order
1. **A first** (switchable + IC flush): unblocks the majority (virtual/instance)
   patch surface, smaller + verifiable on host (re-run the virtual probe).
2. **B next** (static DD): completes coverage for static-helper crash fixes.
3. Then CLI (diff → changed set → bytecode module [+ slot updates]) → engine-shell
   integration (updater loads patch, transplants, flushes/updates slots at boot)
   → iOS rebuild → on-device round-trip (iPhone 14 Pro).

## Build log (own-engine grind)

- **2026-06-25 — post-precompile transplant is IGNORED by the AOT serializer
  (verified, dead end).** Added an env-gated build-time transplant in
  gen_snapshot AFTER `Dart_Precompile()` (load patch bytecode component +
  `Dart_SankofaTransplantBytecode` compute<-patched). It serialized cleanly
  (no crash) BUT the resulting snapshot still ran the NATIVE `compute()` (=BASE)
  on `dartaotruntime_product`. Reason: the AOT serializer writes the
  precompiler's finalized code/instructions tables, not post-hoc `Function.code`
  changes. **Conclusion: changed functions must be emitted as bytecode INSIDE
  the precompiler so the finalized tables reflect it.** Reverted the probe.
- **2026-06-25 — pre-precompile transplant CRASHES the precompiler (SEGV,
  si_addr=-1).** Moved the transplant BEFORE `Dart_Precompile` (so the function
  is `is_declared_in_bytecode` when the precompiler runs) and added a
  `CompileFunction` early-return for bytecode functions. The transplant logged
  OK, then gen_snapshot SEGV'd during precompile/serialize (release build = no
  symbolized frames). So the `CompileFunction` skip is necessary but NOT
  sufficient — the precompiler's reachability trace (`ProcessFunction`/
  `AddCalleesOf`), finalization, and/or the serializer don't handle a function
  whose body is bytecode. Bytecode functions never appear in a normal AOT
  snapshot, so every native-only assumption in that pipeline must be taught to
  handle them. Scaffolding left in place (env-gated `SANKOFA_GENSNAP_PATCH`,
  harmless to normal builds). **Next debugging step: lldb or a debug gen_snapshot
  to symbolize the SEGV, then handle bytecode functions in the precompiler
  reachability + add the Bytecode serialization cluster.** This is the deep core
  of the multi-week build.
- **2026-06-25 — SEGV diagnosed via lldb: `KernelProgramInfo::KernelLibraryStartOffset(-1)`.**
  The transplanted bytecode function's class carries `kernel_library_index = -1`
  (set at object.cc:8328 for component-loaded classes) and/or a null
  `kernel_component`. The precompiler/serializer kernel-access path calls
  `KernelLibraryStartOffset` (object.cc) WITHOUT the `-1` guard that exists at
  object.cc:11458 — `ASSERT(library_index >= 0)` is compiled out in release →
  `blob.DataAddr(neg)` SEGV. So a base function given a patch-component's
  bytecode has inconsistent kernel metadata, and the native-only AOT pipeline
  trips on it. **Fix direction:** the bytecode component must be integrated so
  the transplanted function's kernel metadata is consistent (or the relevant
  kernel-access paths must guard `-1`/handle bytecode functions). This is the
  first of the native-only assumptions to fix; expect more crashes downstream
  (serializer Bytecode cluster, dispatch entries). WIP scaffolding (env-gated
  `SANKOFA_GENSNAP_PATCH` in gen_snapshot.cc + CompileFunction skip in
  precompiler.cc) lives in the ENGINE TREE only (harmless to normal builds);
  sync to the fork once the integration works.
- **2026-06-25 — cross-program build-time transplant is the WRONG FOUNDATION
  (ruled out after grinding 2 crashes).** Guarded `KernelLibraryStartOffset`/
  `EndOffset` for null-blob + `-1` + out-of-bounds index (object.cc) — each fix
  advanced to the NEXT crash in the same kernel-metadata path. Root cause: a
  function transplanted with bytecode from a SEPARATE dart2bytecode component
  carries that component's program metadata (kernel_library_index, kernel_component,
  AND the bytecode's constant-pool refs point into the patch component). The
  precompiler/serializer pervasively assume one consistent program, so guarding
  symptoms won't converge, and dropping the patch library would dangle compute's
  bytecode pool refs. **CONCLUSION: the bytecode for changed functions must be
  generated IN the base program (one kernel), not transplanted from a separate
  component.** The proper hard way = teach gen_kernel/the front_end (pkg/dart2bytecode
  + pkg/vm kernel_front_end) to emit a HYBRID KERNEL where the changed functions
  carry bytecode and the rest carry IL, all in one program; then gen_snapshot
  keeps bytecode for those (CompileFunction skip) + AOT-compiles the rest, and
  the serializer carries the Bytecode (consistent metadata). The object.cc guards
  are harmless defensive code; the transplant scaffolding in gen_snapshot.cc is a
  dead end for production (keep only as the runtime-execution proof). NEXT:
  in-program hybrid-kernel emission in the Dart front_end.
- **2026-06-25 — IN-PROGRAM hybrid design SCOPED (the correct path, all integration points located).**
  Why cross-program failed: `dart2bytecode` (dart2bytecode.dart:318/327) PREFIXES
  the new libraries and only emits bytecode for libs NOT in the base
  (`loadedLibraries`) → the module is a separate program. Fix: generate the
  changed-fn bytecode from the SAME `Component` the kernel was compiled from, so
  all canonical names/refs match the base program. Integration points:
  - `generateBytecode(component, sink, libraries:..., ...)` (pkg/dart2bytecode/
    lib/bytecode_generator.dart:60) emits bytecode PER-LIBRARY for the given
    `libraries` of a Component. Run it on the SAME Component gen_kernel compiled,
    passing the CHANGED libraries (coarse but correct; per-function selectivity =
    later optimization via a custom visitLibrary filter).
  - `pkg/vm/bin/gen_kernel.dart` / `pkg/vm/lib/kernel_front_end.dart` (no bytecode
    refs today) is where to emit IL kernel + the same-Component bytecode component
    as a paired artifact.
  - gen_snapshot MERGE-loads that bytecode component into the IL program (refs
    resolve to existing libs because same compile), marks fns is_declared_in_bytecode;
    `Precompiler::CompileFunction` skip (already added) keeps them; rest AOT.
  - Then: Bytecode serialization cluster (app_snapshot.cc, model on kCodeCid:7802)
    + build-time dispatch trampolines (`R0=fn; jmp InterpretCallStub`, since
    EmitDispatchTableCall doesn't set R0/FUNCTION_REG) + deserializer.
  BUILD ORDER: (1) a tool/gen_kernel mode emitting IL + same-Component bytecode for
  marked libs → (2) gen_snapshot merge-load (verify no cross-program crash; the
  consistency should avoid the KernelLibraryStartOffset class of crashes) →
  (3) Bytecode serialization cluster → (4) run hybrid.aot, verify changed fn
  interprets while rest is native (no JIT) → (5) trampolines for virtual →
  (6) DD for static unchanged→changed → (7) engine-shell + iOS device.
- **NEXT STEP (exact):** in `Precompiler::CompileFunction` (precompiler.cc:3660),
  for a function in the "changed set", attach its bytecode + set
  `is_declared_in_bytecode` + `SetInstructions(StubCode::InterpretCall())` and
  SKIP `helper.Compile()` — so the precompiler treats it as a bytecode function
  from the start. Prereqs: (a) the changed fns' bytecode must be available during
  precompile (load the dart2bytecode component before CompileAll, transplant onto
  the existing Function objects — same primitive, earlier in the pipeline);
  (b) the AOT serializer must serialize `is_declared_in_bytecode` functions'
  Bytecode object — normal AOT snapshots have none, so this is the Bytecode
  serialization cluster to ADD in app_snapshot.cc (no kBytecodeCid cluster
  today → it will FATAL/UnexpectedObject; that error will pinpoint the fields to
  serialize). (c) Then dispatch trampolines (build-time `R0=fn; jmp
  InterpretCallStub`) for the virtual case — the InterpretCall stub expects the
  Function in R0/FUNCTION_REG (stub_code_compiler_arm64.cc:3176), which
  EmitDispatchTableCall does NOT set.

## Injection points (grounded)
- static call lowering:  `runtime/vm/compiler/backend/flow_graph_compiler.cc:956`
- virtual call lowering: `runtime/vm/compiler/backend/il.cc:5435`
- table-call selection:  `runtime/vm/compiler/aot/aot_call_specializer.cc:1223`
- dispatch table gen:    `runtime/vm/compiler/aot/precompiler.cc:488` / `2046`
- transplant primitive:  `runtime/vm/dart_api_impl.cc` `Dart_SankofaTransplantBytecode`
- bytecode→interpret:    `runtime/vm/object.cc:8424` (`Function::AttachBytecode`)

## Build-loop gotchas
- `dart_api.h` AND `dart_api_impl.cc` are in the snapshot-version-hash set →
  editing either bumps the version → must rebuild gen_snapshot + gen_kernel +
  dart2bytecode + vm_platform_product.dill + all artifacts, else "Wrong full
  snapshot version". (`runtime/vm/sankofa_codepush_read.cc` and
  `bin/analyze_snapshot.cc` are NOT in the set → cheap rebuilds.)
- Engine tree (`sankofa-flutter/engine/src/flutter/third_party/dart`, Dart 3.12.1)
  has its OWN copy of every file; fork (`sankofa-dart-sdk`, 3.11.5) is canonical.
  Apply edits to each tree's own version (upstream files differ across versions);
  sankofa-authored files are cp-safe.
