# Sankofa CodePush — engine-shell boot integration (the on-device wiring)

The host harness (`research/fusion/override_in_place`, `cli_v0`) proves the full
apply logic device-free. This is how that same logic runs on the iPhone at boot.

## What's wired (engine edits — all NON-version-hash)

1. **Boot apply hook** — `flutter/runtime/dart_isolate.cc`
   `DartIsolate::SankofaApplyBootPatch(root_library)`, called from
   `RunFromLibrary` **before** `InvokeMainEntrypoint`. If `SANKOFA_PATCH_DIR`
   contains `sankofa_patch.bytecode` + `sankofa_patch.names`, it
   `Dart_LoadLibraryFromBytecode`s the module and `Dart_SankofaTransplantBytecode`s
   each named fn onto the base app fn. The fn's Code becomes the InterpretCall
   stub → new body runs via `dart::Interpreter::Run`, **no JIT**. Boot-time =
   call sites are fresh, so no IC flush needed. Failures log + boot continues.

2. **Virtual entry-boundary rerouting** (so the Flutter framework → your
   `build()` reaches the patched code):
   - `runtime/vm/compiler/aot/aot_call_specializer.cc` — `SANKOFA_NO_TABLE_DISPATCH`
     keeps instance calls switchable (not baked dispatch-table calls).
   - `runtime/vm/runtime_entry.cc` `DoICDataMissAOT` — bytecode targets skip the
     monomorphic fast-path (which never loads FUNCTION_REG) and stay on the
     IC-through-code path, which DOES load FUNCTION_REG = what InterpretCall wants.

3. **Transplant primitive** — `runtime/vm/dart_api_impl.cc`
   `Dart_SankofaTransplantBytecode` (+ decl in `include/dart_api.h`).

## The patch artifact (what the CLI emits / the updater stages)

`make_and_apply_patch.sh` stages `patch_out/`:
- `sankofa_patch.bytecode` — the changed-set module (dart2bytecode, prefixed).
- `sankofa_patch.names` — comma-separated app-scoped changed fn names (the diff's
  `library_uri`-scoped set).

On device these go into `SANKOFA_PATCH_DIR` (the updater's staged-patch dir).

## Device runbook (iPhone 14 Pro)

1. **Build the iOS engine** with the edits (local M2, see
   `project_local_engine_build_proven`): `ios_release` (+ `mac_release_arm64`
   host gen_snapshot, already built). The app's AOT must be produced by THIS
   gen_snapshot with `SANKOFA_NO_TABLE_DISPATCH=1` in the build env so instance
   calls are switchable.
2. **Build a demo app** against the Sankofa engine (the crash-fix demo: a screen
   whose `build()`/handler hits a bug; ship the fixed version as the patch).
3. **Baseline**: run the unpatched app → observe the crash/old behavior.
4. **Stage the patch**: `make_and_apply_patch.sh` → copy `patch_out/*` into the
   app's `SANKOFA_PATCH_DIR` (set the env / write to the app sandbox dir the
   updater uses). Relaunch.
5. **Expect**: boot log `[sankofa] boot code-push applied: N transplanted, 0
   failed`, and the app runs the fixed code — no crash, no JIT, no App Store
   round-trip.

## Notes / next

- The boot hook reuses the EXACT sequence proven on host
  (`analyze_snapshot --bytecode_patch --patch_fns`). Compiling ≠ working: the
  device run is the proof.
- `SANKOFA_PATCH_DIR` is the v0 contract; production wires this to the Rust
  updater's staged-patch path + version/rollback metadata.
- Cascade depth / DD remain a later size optimization; not needed for correctness.
