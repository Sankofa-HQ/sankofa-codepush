# dispatch-funcreg — flag-free virtual-entry-boundary code-push (proven on iPhone)

The production replacement for the dead `SANKOFA_NO_TABLE_DISPATCH` flag (which
SIGSEGV'd the full Flutter framework). Lets an **unchanged base-AOT virtual
dispatch-table call** (the Flutter framework → your `build()` case) reach a
**downloaded bytecode patch** through the interpreter — no flag, no JIT, no
App-Store round-trip.

## Proven on device (iPhone 14 Pro, 2026-06-29)

Pulled straight off the phone (`Documents/sankofa_updater/patches/1/sankofa_boot_result.txt`):

```
transplanted=2 failed=0 repointed=2 verify=render-> PATCH-UI-FIXED   (clean boot, no crash)
```

**Change-only-the-patch proof** (airtight: app binary NOT rebuilt/reinstalled —
mtime unchanged, contains `V2-LIVE` 0×; only the 790-byte `dlc.vmcode` changed,
contains `V2-LIVE` 1×):

```
verify=render-> PATCH-UI-FIXED-V2-LIVE
```

The new marker exists nowhere in the app — it can only come from the downloaded
patch. So this is a real code patch, not a rebuild/rerun.

## Mechanism (engine)

- Dart SDK fork — branch `feat/sankofa-dispatch-funcreg`, commit `05dea581845`:
  interleaved `[entry, function]` dispatch table; HasBytecode-gated parallel
  `dispatch_table_function_entries`; `ReadDispatchTable` stride-2 + function-half
  fill + bytecode-slot → `SankofaDispatchInterpret` trampoline; arm64
  `EmitDispatchTableCall` loads the function-half into R8; `il.cc` always sets
  ARGS_DESC_REG; apply-path APIs `Dart_SankofaCodeEntryForName` /
  `Dart_SankofaRepointDispatchToInterpret`.
- Engine shell — branch `feat/ota-productize`, commit `4f08c4f3ca1`:
  `SankofaApplyBootPatch` parses a comma-separated `target=source` String
  manifest, transplants base[target] ← patch[source] (mapped names), repoints
  the target's dispatch slots.

## The patch (this folder)

- `devicepatch/patch_module.dart` — TOP-LEVEL source fns with constant-return
  bodies (no class → no `Object.` ctor; no list literal → no `_GrowableList`)
  so the patch references ZERO base-SDK callables and loads on a slim AOT app.
  `_sankofaManifest()` returns a comma-separated `target=source` String.
- `devicepatch/base.dart` — minimal mirror (Panel/Panel2/renderPanel) for the
  patch's `--import-dill` base.
- `devicepatch/build_patch.sh` — base no-aot kernel → `dart2bytecode` → 790-byte
  `patch.bytecode`.
- `app/main.dart` — demo app: `Panel.label()` (BASE) reached via base-AOT
  `renderPanel()`; the boot hook fires `sankofaVerify()` (the rerouted dispatch)
  and the UI reads the recorded result via the data-container path (no
  path_provider → avoids the objective_c native-assets build break).

## Device flow

`devicepatch/build_patch.sh` → `stage_device.sh patch` (push `dlc.vmcode` +
pointers, launch) → pull `sankofa_boot_result.txt`. `stage_device.sh base`
clears. Host gate: `run_reroute.sh` / `hostcheck.sh` against `/tmp/appbase.aot`
(mac gen_snapshot of the app's `app.dill`) reproduces device behavior exactly.

## Known limit (next frontier)

Driving the rerouted call **live during the full Flutter render** (`panelStatus()`
in `build()`) crashes the β.3 interpreter: `interpreter.cc:3426 UNIMPLEMENTED
opcode=0` (zero bytecode) after a 125-deep framework recursion — NOT over-repoint
(`repointed=2` is exactly the two correct slots). So this build exercises the
reroute via the boot-hook fresh invoke (simple context, interpreter solid) and
the UI displays the recorded result. A fully-live render reroute needs β.3
interpreter completeness.
