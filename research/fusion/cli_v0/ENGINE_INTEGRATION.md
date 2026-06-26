# Sankofa CodePush — engine-shell boot integration (the on-device wiring)

The host harness (`research/fusion/override_in_place`, `cli_v0`) proves the full
apply logic device-free. This is how that same logic runs on the iPhone at boot,
wired into the **real updater pipeline** (no env-var shortcut).

## What's wired (engine edits — all NON-version-hash)

1. **Boot apply hook** — `flutter/runtime/dart_isolate.cc`
   `DartIsolate::SankofaApplyBootPatch(root_library)`, called from
   `RunFromLibrary` **before** `InvokeMainEntrypoint` (isolate ready, snapshot
   loaded, `main()` not yet run → call sites fresh → no IC flush). It reads the
   staged patch path (set by the shell, see #4), `Dart_LoadLibraryFromBytecode`s
   the module, calls the module's embedded `_sankofaManifest()` for the changed
   set, and `Dart_SankofaTransplantBytecode`s each onto the base fn. New bodies
   run via `dart::Interpreter::Run`, **no JIT**. Missing patch → normal boot;
   failures log + never abort.

2. **Virtual entry-boundary rerouting** (Flutter framework → your `build()`):
   - `runtime/vm/compiler/aot/aot_call_specializer.cc` — `SANKOFA_NO_TABLE_DISPATCH`
     keeps instance calls switchable (not baked dispatch-table calls).
   - `runtime/vm/runtime_entry.cc` `DoICDataMissAOT` — bytecode targets skip the
     monomorphic fast-path (no FUNCTION_REG) and stay on IC-through-code (loads
     FUNCTION_REG = what InterpretCall needs).

3. **Transplant primitive** — `dart_api_impl.cc` `Dart_SankofaTransplantBytecode`.

4. **Patch path from the real updater (shell)** — `DartIsolate::SetSankofaBootPatchPath`
   (runtime, libupdater-free) is fed by the shell's `ConfigureSankofa`:
   `sankofa_init` → `sankofa_next_boot_patch_path()` (download / Ed25519-verify /
   version-select / rollback all handled by the Rust updater) →
   `sankofa_report_launch_start()` → `SetSankofaBootPatchPath(path)`. After boot,
   the Shell calls `sankofa_report_launch_success()` (grace-window completion;
   `sankofa_report_launch_failure` / boot-crash detect roll back). **STATUS: hook
   + path-store DONE + compile-verified; ConfigureSankofa + Shell success-call +
   BUILD.gn libupdater link = the remaining shell wiring (next).**

## The patch artifact (one self-contained file)

`make_and_apply_patch.sh` builds `patch_out/sankofa_patch.bytecode` — the changed
set + a generated `_sankofaManifest()` + a dyn-module entry retaining them. The
updater stages this single file; the hook reads the manifest from inside it.
(Signing = v2 Ed25519 envelope, the CLI's existing path.)

## Vendored updater (gitignored — populated by the vendoring step)

`engine/src/flutter/third_party/updater/` (gitignored) holds:
- `lib/{ios-arm64,arm64-v8a,armeabi-v7a,x86_64}/libupdater.a` (built from
  `sankofa-codepush/updater`, `cargo build --release` per target triple).
- `include/updater_engine.h` (cbindgen output, copied from
  `sankofa-codepush/updater/library/include/`).
A vendoring script should refresh both from the updater crate.

## Device runbook (iPhone 14 Pro)

1. Finish the shell wiring (#4) + BUILD.gn: link `third_party/updater` into the
   shell target; add `ConfigureSankofa` (called from the iOS/Android embedder
   startup, like Shorebird's `ConfigureShorebird`) + the Shell success call.
2. **Build the iOS engine** (`ios_release`) with these edits (local M2;
   needs the Metal Toolchain: `xcodebuild -downloadComponent MetalToolchain`).
3. **Build a demo app's AOT** with the Sankofa gen_snapshot and
   `SANKOFA_NO_TABLE_DISPATCH=1` (so instance calls are switchable).
4. **Baseline**: run unpatched → observe the crash.
5. `make_and_apply_patch.sh` → upload the signed patch → the updater downloads +
   stages it → relaunch.
6. **Expect**: `[sankofa] boot code-push applied: N transplanted, 0 failed` and
   the crash gone — no JIT, no App Store round-trip.

Compiling ≠ working: the device run is the proof.
