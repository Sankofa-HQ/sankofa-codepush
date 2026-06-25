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
