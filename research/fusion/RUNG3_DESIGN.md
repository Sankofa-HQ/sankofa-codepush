# RUNG-3 — bytecode-shaped changed functions + interpreter handoff

**The last piece of the dream: an actual CHANGED function (a real crash fix /
behavior change) shipped over-the-air and running on a stock-signed, no-JIT iOS
app — on Sankofa's own Flutter engine.**

Status: design + plan. Rungs 1–2 proven; this is rung-3.

> ## ⭐ SUPERSEDING UPDATE (2026-06-30): fusion is now an OPTIMIZATION, not the path to arbitrary logic
>
> The premise that drove this doc — that arbitrary patch logic NEEDS fusion to
> escape a private-impl "retention ceiling" — turned out to be **false**. The
> `--dynamic-interface` build auto-runs `discoverLanguageImplPragmasInCoreLibraries`,
> which retains the private impls language features lower to (`_GrowableList`,
> `_StringBase._interpolate`). **Arbitrary logic (list literals + interpolation +
> control flow + method calls) is PROVEN live on the iPhone via the
> dispatch-funcreg path** (`dispatch_funcreg/README.md` Test #2:
> `render-> PATCH-UI-FIXED computed sum=55 n=5 [i1+i2+i3+i4+i5]`). No fusion VM
> surgery, no manual curation.
>
> Two further dead premises corrected during this recon:
> - The precompiler does NOT auto-walk a bytecode function's callees
>   (`ProcessFunction`/`CompileFunction` early-return before `AddCalleesOf`), so
>   fusion would have needed the SAME retention anyway — it was never the
>   retention escape hatch.
> - The β.3 interpreter is complete enough for real logic (the earlier "interpreter
>   incompleteness" was the buffer-lifetime bug, now fixed).
>
> **Fusion's remaining value = an OPTIMIZATION:** offset-linked patches are tiny
> (99.6% reuse base) and unchanged code keeps running native AOT instead of
> interpreted (faster, lower memory). Pursue it for production efficiency, NOT as
> the enabler of arbitrary logic. The rest of this doc remains the fusion rung-3
> plan; it's now an optional optimization track.

---

## 0. The dream (north star — don't lose it)

Ship a Flutter app to the App Store. Later, find a crash or need a behavior
change. Push a tiny patch from `api.sankofa.dev`. The *installed, signed* app —
no resubmission, no JIT, no executable download — picks it up at next launch and
runs the new code. App-Store-legal because the patch's machine code is **never
executed**: changed functions run through the **Dart bytecode interpreter** (an
interpreter over data is explicitly permitted; see
`reference_app_store_policy_compliance`), unchanged code keeps running the
original signed AOT.

This is the moat: tools are open, but `api.sankofa.dev` + our own engine deliver
the one thing competitors' hosted infra gates. Two delivery mechanisms converge
here (see §3); rung-3 is where "change a function" finally works on device.

---

## 1. Where we are (the two proven halves that meet at rung-3)

### Half A — data-only fusion (this doc's track)
- **Rung-1 (link):** ✅ proven at 17,273-fn real Flutter-app scale. A
  deterministic analyzer hash (`subgraph_hash`, with native-function addresses /
  class-cids / pool-indices scrubbed) makes a patch link 100% vs an
  identical-source base and 99.6% on a one-leaf change. `aot_tools link` →
  `.vmcode` (`[count u32BE][(sim,cpu)×count][pad 16384]` + patch ELF).
- **Rung-2 (fusion executes):** ✅ **proven on iPhone 14 Pro (2026-06-29).** A
  100%-link patch boots via `Dart_CreateIsolateGroupWithBaseSnapshot`, survives
  first-frame GC, renders the full UI, stable. Four VM fixes made it work:
  16 KB-page link padding; reverse-fuse base-PC→patch-PC (`FindCode`/`FindEntry`,
  `Dart_SankofaBasePcToPatchPc`); `LinkNativeCall` guard (skip self-modifying the
  read-only base call site); `FindStackMap` base-space `start_pc` (GC roots).
- The resolver already **selects** changed vs unchanged
  (`Dart_SankofaResolveEntryPoint`, sankofa_codepush_read.cc:597): offset in the
  link table → base image (unchanged); offset absent → changed → "keep in the
  patch image → the interpreter handoff runs it." **The selection is done; the
  handoff is the gap.**

### Half B — dispatch-funcreg interpreter handoff (proven 2026-06-30, TODAY)
- A downloaded **bytecode** function runs through the **interpreter**
  (`Function::AttachBytecode` → `InterpretCall` stub → `dart::Interpreter::Run`),
  live, no JIT, on device — including non-trivial logic (loop + arithmetic +
  `int.toString` + `String.+`, computed `sum=55`).
- Fixed the buffer-lifetime bug that would have sunk it
  (`Dart_NewExternalTypedDataWithFinalizer` keeps the patch mapping alive for the
  isolate's life — without it the interpreter Trapped on freed instruction bytes).

**The convergence:** Half A selects *which* functions changed and supplies the
full base (so callees resolve). Half B *runs* a changed function from downloaded
bytecode through the interpreter. **Rung-3 = wire Half B into Half A's
changed-Code path.** Today's work was not a detour; it built fusion's missing
execution primitive.

---

## 2. The resolver today (grounded)

`Dart_SankofaResolveEntryPoint(patch_image_start, pc_offset)`
(sankofa_codepush_read.cc:597) is called during deserialization to assign every
Code its entry point:

```
if (link table empty)            return patch_image_start + pc_offset;  // base-only, passthrough
if (pc_offset in link table)     return base_instructions + cpu_offset; // UNCHANGED → base AOT (executable)
else                             return patch_image_start + pc_offset;  // CHANGED → patch image
```

On iOS the patch image is mapped **kReadOnly** (no PROT_EXEC), so the last branch
returns a PC that **cannot be executed**. Rung-2 worked only because a 100%-link
patch never takes that branch (every Code is unchanged → base). The moment one
function changes, its Code takes the `else` branch → a jump into non-executable
memory → crash. **That `else` branch is the rung-3 splice point.**

---

## 3. Rung-3 architecture

Three pieces. Pieces 1–2 are the work; piece 3 is the property that makes it
worth doing (and the key risk to validate).

### Piece 1 — bytecode-shaped patch (the changed functions carry bytecode)
The patch image is native AOT (`gen_snapshot --snapshot_kind=app-aot-elf`); it
has **no bytecode**. The interpreter needs bytecode for a changed function. So
the patch must additionally carry **bytecode for the changed functions**.

Two ways to produce it:
- **(1a) gen_snapshot emits changed fns bytecode-shaped.** During the patch
  build, the functions that differ from base are compiled to KBC bytecode
  (dart2bytecode path) and embedded in the patch alongside the native AOT. The
  fusion knows them by the same offset/identity it uses for selection. Cleanest
  end-state; needs gen_snapshot work.
- **(1b) Side bytecode module (reuse dispatch-funcreg).** Ship the changed
  functions as a separate `dart2bytecode` module (exactly today's proven path)
  *alongside* the `.vmcode`. The fusion handles unchanged (base); the boot hook
  `AttachBytecode`s the changed functions onto the fused isolate. Fastest to a
  device proof because the module-load + attach path is already proven today.

**Recommended first step: 1b** — it reuses today's proven machinery and gets a
changed function running on the fused base in one device cycle, before investing
in gen_snapshot bytecode emission (1a) for the productized single-artifact form.

### Piece 2 — the interpreter handoff (the splice)
For a **changed** Code, instead of (or in addition to) returning a non-executable
patch-image PC, make the Code run through the interpreter:
- Attach the changed function's bytecode (`Function::AttachBytecode`) — proven.
- Set its entry to the `InterpretCall` stub so any call enters
  `dart::Interpreter::Run` — proven.
- The dispatch-table slot (for virtual targets) repoints to the
  `SankofaDispatchInterpret` trampoline — proven (dispatch-funcreg).

Splice location: the deserialization/entry-assignment path that calls
`Dart_SankofaResolveEntryPoint`. When that function would take the CHANGED branch
(`resolve_patch_hits++`), the engine instead routes that Code's function to the
interpreter (attach bytecode + InterpretCall entry). In the **1b** variant this
happens in the boot hook after fusion creation (attach by name, like today); in
**1a** it happens inside the resolver/deserializer keyed by offset.

### Piece 3 — callee resolution + THE RETENTION QUESTION (why fusion, not just transplant)
When the interpreted changed function calls something, the callee must resolve.

- **dispatch-funcreg alone** resolves callees **by name** against the base app's
  AOT → needs `--dynamic-interface` to retain the named callable, and *cannot*
  reach private impls language features lower to (`_GrowableList`,
  `_StringBase._interpolate`) — the ceiling we hit in test #1.
- **fusion's promise:** the patch is a **full recompile** of the app, so the
  changed function and everything it needs exist in the patch; unchanged callees
  map (by the link table, by offset) to the base's executable code. A list
  literal's `_GrowableList` is unchanged → maps to the **base's** `_GrowableList`
  (the base app uses lists everywhere → it's there). **No name-based retention,
  no `--dynamic-interface`, no private-impl ceiling** — *if* the interpreted
  changed function's calls resolve through the fused snapshot rather than a bare
  name lookup.

⚠ **This is the #1 thing to validate.** The interpreter resolves a bytecode call
via the bytecode's constant pool / selector. We must confirm that, in the fused
isolate, those resolve against the patch's full pool + the base via the link
(offset) — NOT a tree-shaken name lookup. If they resolve by name only, the
private-impl ceiling could re-appear and we'd need 1a (gen_snapshot bytecode that
carries the pool refs) rather than 1b (a side module). The host ladder (§4)
answers this before any device cycle.

---

## 4. Validation ladder (host first — the proven methodology)

Each rung cheap→dear; do not skip.

1. **Host, selection (done):** `analyze_snapshot --fusion_selftest --link_table`
   → base_hits/patch_hits correct on a 1-fn change. ✅ already proven.
2. **Host, changed-fn INTERPRETED:** extend the fusion harness so a changed
   Code runs through the interpreter (not the host-executable patch native).
   Prove the changed function returns its NEW value via the interpreter, and —
   critically — that its callees (incl. a list literal / interpolation) resolve
   against the fused base **without `--dynamic-interface`**. This answers the §3
   retention question with no device cost. ← **START HERE.**
3. **Device, 1b (side bytecode module on fused base):** rebuild test app vs the
   fusion engine; ship `.vmcode` (link) + a bytecode module (changed fns); boot
   → fusion creates the isolate, boot hook attaches the changed fns' bytecode →
   the changed function runs interpreted, callees resolve against the base. The
   first real "changed function on device via fusion."
4. **Device, real crash fix:** ship a patch that fixes an actual thrown
   exception (e.g. the `risky(0)` division-by-zero from the original dream) and
   watch it go from crash → fixed, live, no retention, no JIT.
5. **Productize (1a):** gen_snapshot emits changed fns bytecode-shaped into the
   single `.vmcode`; `sankofa patch` generates it from a diff; server delivery
   (proven for the transplant path) + signed envelopes + rollback grace window.

---

## 5. Exact splice points (code)

| Concern | File:symbol | Action |
|---|---|---|
| Changed-Code selection (done) | `vm/sankofa_codepush_read.cc:597` `Dart_SankofaResolveEntryPoint` | `else` branch = changed; route to interpreter instead of patch PC |
| Interpreter handoff | `vm/dart_api_impl.cc` `Dart_SankofaTransplantBytecode` / `Function::AttachBytecode` | attach changed fn bytecode + InterpretCall entry (proven) |
| Mapping lifetime | `flutter/runtime/dart_isolate.cc` `SankofaApplyBootPatch` | `Dart_NewExternalTypedDataWithFinalizer` (proven fix) |
| Fusion boot | `flutter/runtime/dart_isolate.cc` `SankofaTryLoadFusionPatch` (+ `g_sankofa_fusion_active` branch) | after create, attach changed-fn bytecode (1b) |
| Bytecode-shaped emit (1a, later) | `gen_snapshot` / dart2bytecode path | emit changed fns as KBC in the patch |
| Host harness | `bin/analyze_snapshot.cc` `--fusion_run` | add interpreter-handoff mode for changed Codes |

---

## 6. Open questions / risks (honest)
- **Callee resolution path (the big one):** name-lookup vs fused-snapshot/offset
  for an interpreted changed function's calls (§3). Decides 1b-viability and
  whether the private-impl ceiling returns. Rung 4.2 answers it.
- **Selection granularity:** the resolver keys on instructions offset; a changed
  function's *callers* may also need rerouting (the cascade) — but rung-1 showed
  a 1-leaf change links 99.6% (only the leaf + direct caller ship), and the
  dispatch-funcreg reroute already handles caller→changed virtual edges.
- **Bytecode for arbitrary functions:** dart2bytecode handling of closures,
  async, generics in a changed fn — exercise incrementally (dispatch-funcreg
  proved straight-line + loops + calls; widen coverage).
- **Version dance discipline:** any VM-hashed source edit churns the snapshot
  hash → rebuild engine + universal gen_snapshot + app + patch together. Each VM
  fix = one device cycle. (interpreter.cc / dart_isolate.cc are NOT hashed →
  cheap; app_snapshot.cc / object.cc ARE → full dance.)
- **Device flakiness:** iPhone drops off the CoreDevice tunnel when locked; keep
  Auto-Lock=Never during runs.

---

## 7. What today's dispatch-funcreg win contributes (so it's not re-derived)
- Proven: `AttachBytecode` + `InterpretCall` + `SankofaDispatchInterpret`
  trampoline run downloaded bytecode through the interpreter on device, no JIT.
- Proven: non-trivial logic (control flow + arithmetic + method calls) runs.
- Fixed: patch mapping lifetime (`Dart_NewExternalTypedDataWithFinalizer`).
- Learned: name-based callee resolution needs retention (`--dynamic-interface`,
  public-only) — which is *exactly* why rung-3 leans on fusion's offset/base
  resolution to escape the ceiling. The limitation found today motivates the
  fusion path chosen here.

Backups: engine-tree Dart (can't push) → full-series patch in
`engine_patches/`; engine shell pushed to `sankofa-flutter` `feat/ota-productize`;
this track's memory: `project_dispatch_funcreg_live_render_proven`,
`project_data_only_fusion_selection_proven`.
