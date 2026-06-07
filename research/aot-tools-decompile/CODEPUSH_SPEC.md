# Sankofa CodePush — Patch Pipeline Spec (reverse-engineered from aot-tools.dill)

**Source**: decompiled `aot-tools.dill` (Apache-2.0 binary) extracted via
`pkg/kernel/binary/ast_from_binary.dart` (Dart 3.13/stable, format 130).

**Status**: research only, no implementation yet. This doc captures the
external contracts and orchestration. Internal VM modifications still
require porting work in `sankofa-dart-sdk`.

**Files in this directory**:
- `aot_tools_full_dump.txt` — every aot_tools library decompiled (~3900 lines)
- `snapshot_analysis_only.txt` — just `package:aot_tools/src/snapshot_analysis.dart`
- `CODEPUSH_SPEC.md` — this file (the synthesized spec)

---

## 1. The `.vmcode` file (what ships to the device)

```
[ LinkTable header — see §4 ]
[ Optimized patch AOT-ELF snapshot bytes — see §3 ]
```

The header is page-padded to **4096-byte alignment** so the engine can
mmap the snapshot portion directly. Total size = header + patch snapshot.

---

## 2. `analyze_snapshot --shorebird --out=<path> [--disassemble] <snapshot>`

Reads a Dart AOT snapshot (ELF) and emits this JSON:

```json
{
  "snapshot_data": {
    "vm_data_length": "<num as decimal string>",
    "adjusted_vm_instructions_length": "<num as decimal string>",
    "vm_data_hash": "<num as decimal string>",
    "adjusted_vm_instructions_hash": "<num as decimal string>",
    "dart_version": "<string?>",
    "snapshot_version": "<string?>"
  },
  "functions": [
    {
      "name": "<string>",
      "index_in_entries": <int>,
      "offset": <int>,
      "size": <int>,
      "subgraph_hash": "<long hex>",
      "op_subgraph_hash": "<long hex>",
      "self_hash": "<long hex>",
      "subgraph_pp": [<int>...],
      "self_pp": [<int>...],
      "subgraph_selectors": [<int>...]?,
      "self_selectors": [<int>...]?,
      "subgraph_field_table": [<int>...]?,
      "self_field_table": [<int>...]?,
      "disassembly": ["<string>"...]?
    }, ...
  ]
}
```

### What each field means

- `vm_data_length` / `vm_instructions_length`: the VM-data / VM-instructions
  ELF section lengths. `adjusted_vm_instructions_*` = with codepush-mode
  padding removed (so two snapshots from the same kernel match exactly).
- `name`: mangled Dart function name (e.g. `dart::core::print`).
- `index_in_entries`: position in the snapshot's `Code` entries array.
- `offset` / `size`: bytes from start of instructions section.
- `subgraph_hash`: hash over this function + everything it transitively
  calls. Used by the linker to match base ↔ patch functions.
- `op_subgraph_hash`: same but only counts the object-pool entries
  referenced. Used to detect when object-pool changes break a function.
- `self_hash`: hash of just this function's own IL (no transitive deps).
- `subgraph_pp` / `self_pp`: indices into the object pool for the
  subgraph and self respectively.
- `subgraph_selectors` / `self_selectors`: dispatch-table selector
  offsets used by the subgraph / self.
- `subgraph_field_table` / `self_field_table`: field-table offsets used.
- `disassembly`: present only with `--disassemble`. Used for debug.

---

## 3. `gen_snapshot` codepush flag surface

### Base-build mode (during normal `flutter build`)

```
gen_snapshot \
  --snapshot_kind=app-aot-elf \
  --elf=<output.aot> \
  --print_class_table_link_info_to=<base>.ct.link \
  --print_class_table_link_debug_info_to=<base>.class_table.json   [optional]
  --print_dispatch_table_link_info_to=<base>.dt.link \
  --print_dispatch_table_link_debug_info_to=<base>.dispatch_table.json [optional]
  --print_field_table_link_info_to=<base>.ft.link \
  --print_field_table_link_debug_info_to=<base>.field_table.json   [optional]
  --dd_slot_mapping=<base>.dd_slot_mapping                          [optional]
  <gen_snapshot_args (from flutter build)> \
  <kernel.dill>
```

Emits the AOT snapshot **plus** three binary "link data" files that
describe the snapshot's internal layout. The patch build later reads
these to align with the base.

### Patch-build mode (called by `aot_tools link`)

```
gen_snapshot \
  --snapshot_kind=app-aot-elf \
  --base_ct_link_data=<base.ct.link>      --patch_ct_link_data=<patch.ct.link> \
  --base_op_link_data=<base.op.link>      --patch_op_link_data=<patch.op.link> \
  --base_dt_link_data=<base.dt.link> \
  --base_ft_link_data=<base.ft.link> \
  --dd_slot_mapping=<patch>.dd_slot_mapping            [optional]
  --print_dd_function_identity_to=<patch>.dd_func_id   [optional]
  --print_dd_resolution_to=<patch>.dd_resolution       [optional]
  --print_class_table_link_debug_info_to=<...>         [optional]
  --print_field_table_link_debug_info_to=<...>         [optional]
  --print_dispatch_table_link_debug_info_to=<...>      [optional]
  --elf=<patch.aot> \
  <gen_snapshot_args> \
  <patch.dill>
```

The base/patch link data inputs ensure that:
- Class IDs match the base (so dispatch indices line up)
- Object pool entries are placed at base-compatible offsets
- Field offsets align with the base (so the runtime can find fields by
  their existing slot numbers)
- Dispatch table selector offsets stay stable

This is the **link/relocation pass** — the patch's IL is rewritten to
reference base's class/object/field/dispatch slots, so when the device
loads the patch on top of the base it doesn't need any extra fixup.

---

## 4. LinkTable binary format

Produced by `Linker.link(baseFunctions, patchFunctions)` and serialized
as the prefix of `.vmcode`:

```
[ count : uint32 BE ]
[
  [ sim_offset : uint32 BE ]   ← patch function offset in patch.aot
  [ cpu_offset : uint32 BE ]   ← matching base function offset in base.aot
] × count
[ zero padding → next 4096-byte boundary ]
```

### Linker.link algorithm (verbatim from decompile)

```
1. Group base codes by subgraph_hash → baseHashesToCodes
2. Group patch codes by subgraph_hash → patchHashesToCodes
3. For each (hash, patchList) in patchHashesToCodes:
     baseList = baseHashesToCodes[hash]
     if baseList is null or empty:
       continue  // patch has new functions with no base equivalent
     if patchList.length == baseList.length:
       map patchList[i] → baseList[i] for all i  (in order)
     elif patchList.length < baseList.length:
       map first patchList.length pairs
     else (patchList.length > baseList.length):
       map first baseList.length pairs
       map remaining patchList[i] → baseList.last  // all overflow → last base
4. Return LinkTable(simToCpu=mappings)
```

The order assumption is critical: `Code` entries are produced in
deterministic order by gen_snapshot, so hash collisions resolve
positionally. The validator catches mismatches.

### Device-side application

The updater reads `.vmcode`:
1. Parse the LinkTable (first count*8 + 4 bytes).
2. mmap the snapshot bytes that follow.
3. For each function call site in the patch, translate `sim_offset` →
   `cpu_offset` to point at base's address. Existing engine dispatch
   stays unchanged — the patch only ever calls into the address space
   the base allocated, via this translation table.

---

## 5. Orchestration — `aot_tools link` (5+ stage pipeline)

This is what `aot_tools link --base=A.aot --patch=B.aot --kernel=B.dill --output=B.vmcode` actually does, top to bottom:

```
INPUTS:
  base.aot, base.ct.link, base.dt.link, base.ft.link   (from base build)
  patch.aot, patch.ct.link, patch.dt.link, patch.ft.link (from `flutter build`)
  patch.dill (kernel)
  gen_snapshot_args (passthrough from flutter build, e.g. --strip)

STAGE 0  — Object pool link data for base
  analyze_snapshot --dump_object_pool_link_data=base.op.link base.aot

STAGE 1  — Class-table-only patch build
  gen_snapshot patch-mode:
    classTables={base.ct.link, patch.ct.link}
    baseFieldTable=base.ft.link
  → <patch>.ct.aot

STAGE 2  — Object pool link data for ct.aot
  analyze_snapshot --dump_object_pool_link_data=<patch>.ct.op.link <patch>.ct.aot

STAGE 3  — Pre-DD optimized build
  gen_snapshot patch-mode:
    classTables={base, patch}, objectPools={base, ct}, baseFieldTable,
    baseDispatchTable=base.dt.link, ddFunctionIdentity=preDdOptimized.dd_func_id
  → <patch>.preDdOptimized.aot

STAGE 4  — DD (deferred dispatch) computation [if --dd-max-bytes > 0]
  Stage 4a: analyze_snapshot --compute_dd_table=base.dd_table
                              --dd_caller_links=base.dd_caller_links
                              [--dd_max_bytes=N] base.aot
              (only if base.dd_table/.dd_caller_links don't already exist)
  Stage 4b: analyze_snapshot --compute_dd_slot_mapping=<patch>.dd_slot_mapping
                              --dd_table_data=base.dd_table
                              --dd_caller_links=base.dd_caller_links
                              --dd_function_identity=preDdOptimized.dd_func_id
                              <patch>.preDdOptimized.aot

STAGE 5  — DD-only patch build
  gen_snapshot patch-mode:
    classTables={base, patch}, baseFieldTable, baseDispatchTable,
    ddSlotMapping (from stage 4b)
  → <patch>.ddOnly.aot

STAGE 6  — Object pool link data for ddOnly
  analyze_snapshot --dump_object_pool_link_data=<patch>.ddOnly.op.link <patch>.ddOnly.aot

STAGE 7  — Final optimized patch build
  gen_snapshot patch-mode:
    classTables={base, patch},
    objectPools={base.op.link, <patch>.ddOnly.op.link},
    baseFieldTable, baseDispatchTable, ddSlotMapping,
    ddResolution=<patch>.dd_resolution
  → <patch>.optimized.aot

STAGE 8  — Build the LinkTable
  baseSnapshot  = analyze_snapshot --shorebird base.aot
  patchSnapshot = analyze_snapshot --shorebird <patch>.optimized.aot
  Validate baseSnapshot.snapshot_data == patchSnapshot.snapshot_data
    (same vm_data_length/hash and adjusted_vm_instructions_length/hash)
    — if not, fail with "base and patch snapshots have differing VM sections"
  linkTable = Linker.link(baseSnapshot.functions, patchSnapshot.functions)

STAGE 9  — Emit .vmcode
  .vmcode = linkTable.toBytes(padToAlignment=4096) + read(<patch>.optimized.aot)
```

### Why 5+ stages of gen_snapshot?

Each stage builds an increasingly-aligned patch. Stage 1 fixes class
IDs only. Stage 3 adds object pool alignment. Stage 5 adds DD (which
needs the pre-DD pass to compute the slot mapping). Stage 7 is the
final pass with everything aligned. **Each stage's output influences
the next stage's inputs.**

This is THE most complex part of the patch creation. Skipping stages
produces a snapshot that "works" but is huge (no alignment = lots of
duplicate code). Done right, the patch is just the delta.

---

## 6. What we need to implement in `sankofa-dart-sdk`

### 6a. `analyze_snapshot` (C++ in `runtime/bin/analyze_snapshot.cc`)

Subcommands needed (all reading a Dart AOT snapshot ELF):

| Subcommand | Output | Status |
|---|---|---|
| `--shorebird --out=<path>` | JSON per §2 | **stub today (writes `{}`)**, needs heap walker |
| `--dump_object_pool_link_data=<path>` | binary `.op.link` | stub |
| `--dump-blobs --out=<path>` | binary blobs | stub |
| `--dump_class_table --out=<path>` | JSON class table | stub |
| `--dump_object_pool --out=<path>` | JSON object pool | stub |
| `--compute_dd_table=<path> --dd_caller_links=<path>` | binary DD table | stub |
| `--compute_dd_slot_mapping=<path>` | binary slot mapping | stub |

The hard one is `--shorebird`. We need to walk the snapshot's `Code`
objects and compute:
- subgraph_hash, op_subgraph_hash, self_hash for each
- pp indices (object pool entries referenced)
- selector offsets (dispatch table entries referenced)
- field_table offsets

All this metadata exists in the Dart VM at AOT-compile time but isn't
serialized in the snapshot. We need to either:
- (A) Have gen_snapshot emit it as side-data during snapshot creation
- (B) Reconstruct it from the snapshot ELF by walking pointer references

(A) is cleaner and what Shorebird does (via the `--print_*_link_info_to`
flags). (B) requires intricate ELF + Dart-snapshot-format parsing.

### 6b. `gen_snapshot` (C++ in `runtime/vm/`)

Adding the patch-link-mode flags requires hooks in:

| Hook | Files | Purpose |
|---|---|---|
| Emit `.ct.link` | `runtime/vm/class_table.{h,cc}` | Serialize class IDs + layout |
| Emit `.dt.link` | `runtime/vm/dispatch_table.{h,cc}` | Serialize dispatch table |
| Emit `.ft.link` | `runtime/vm/object_store.{h,cc}` + `field.{h,cc}` | Serialize field-table |
| Emit `.op.link` | `runtime/vm/object_pool.{h,cc}` | Serialize object-pool layout |
| Read base link data | New: `runtime/vm/codepush/{ct,dt,ft,op}_reader.cc` | Load base's serialized layouts |
| Align patch IL | `runtime/vm/compiler/aot/precompiler.cc` | Reuse base's slot offsets |
| Emit DD identity/resolution | New: `runtime/vm/codepush/dd_*.cc` | DD-pass emitters |

Estimated surface: **6–10K LOC of Dart VM modifications**.

### 6c. `aot_tools` replacement (Dart in `pkg/aot_tools/`)

Our own Dart program that orchestrates §5. ~500-1000 LOC of Dart.
Replaces the closed `aot-tools.dill` blob. Calls our `analyze_snapshot`
and `gen_snapshot` binaries with the right flags.

---

## 7. Realistic effort estimate

| Component | LOC (approx) | Effort |
|---|---|---|
| analyze_snapshot heap walker (`--shorebird`) | 2000 | 2–4 weeks |
| analyze_snapshot other subcommands | 1500 | 2 weeks |
| gen_snapshot link-data emitters (4 tables) | 2000 | 3–4 weeks |
| gen_snapshot link-data readers + IL alignment | 3000 | 4–6 weeks |
| DD passes (identity, slot_mapping, resolution) | 1500 | 3 weeks |
| aot_tools orchestrator (Dart) | 800 | 1 week |
| Linker (Dart, but algorithm is tiny) | 200 | 2 days |
| Tests + on-device verification (Android + iOS) | n/a | 2 weeks |

**Total**: **3–4 months** of focused VM-internals work for one person
who knows Dart VM well. **5–6 months** for ramp-up if starting cold.

---

## 8. Risks

1. **Hash compatibility**: Shorebird's hashes might depend on
   internal-state details we don't replicate exactly. If our patch's
   hashes don't match base's hashes for unchanged functions, the
   linker thinks everything's new and the patch is huge.
2. **DD opacity**: Deferred Dispatch is the optimization Shorebird
   guards as their main IP. Skipping it (DD_MAX_BYTES=0) is correct
   but produces 2-3× larger patches. Implementing it from scratch
   needs understanding what it is — and the decompile only shows
   FILE NAMES, not the algorithm. **This is the biggest unknown.**
3. **gen_snapshot test coverage**: Dart VM has integration tests that
   exercise gen_snapshot. Our patches need to pass them, or we'll
   silently break non-codepush builds.

---

## 9. Provenance + licensing

- aot-tools.dill is distributed as part of Shorebird's engine artifacts.
  Their CLI (Apache-2.0) downloads it; the binary itself is unmarked
  but Shorebird's website indicates the project is Apache-2.0.
- Reading + decompiling this binary for **interoperability** is legally
  permitted in most jurisdictions (US 17 USC §1201(f), EU Software
  Directive Art. 6).
- This spec is **derived** from the decompile but expresses interfaces
  in our own words. The actual implementation in `sankofa-dart-sdk`
  must be clean-room (not paste from decompile).
- Generated `.vmcode` files are produced by our tools; the format
  itself is open (documented above).

---

**End of spec.**
