// Sankofa aot_tools — SnapshotAnalysis model
//
// Mirrors the JSON schema documented in
// research/aot-tools-decompile/CODEPUSH_SPEC.md §2, written by our
// analyze_snapshot --shorebird mode.

import 'dart:convert';
import 'dart:io';

/// One function in the snapshot. Field semantics match
/// `package:aot_tools/src/snapshot_analysis.dart::Code`.
class Code {
  Code({
    required this.name,
    required this.indexInEntries,
    required this.offset,
    required this.size,
    required this.subgraphHash,
    required this.opSubgraphHash,
    required this.selfHash,
    required this.subgraphPp,
    required this.selfPp,
    this.subgraphSelectors,
    this.selfSelectors,
    this.subgraphFieldTable,
    this.selfFieldTable,
    this.disassembly,
  });

  factory Code.fromJson(Map<String, dynamic> json) => Code(
        name: json['name'] as String,
        indexInEntries: (json['index_in_entries'] as num).toInt(),
        offset: (json['offset'] as num).toInt(),
        size: (json['size'] as num).toInt(),
        subgraphHash: json['subgraph_hash'] as String,
        opSubgraphHash: json['op_subgraph_hash'] as String,
        selfHash: json['self_hash'] as String,
        subgraphPp: (json['subgraph_pp'] as List).cast<int>(),
        selfPp: (json['self_pp'] as List).cast<int>(),
        subgraphSelectors:
            (json['subgraph_selectors'] as List?)?.cast<int>(),
        selfSelectors: (json['self_selectors'] as List?)?.cast<int>(),
        subgraphFieldTable:
            (json['subgraph_field_table'] as List?)?.cast<int>(),
        selfFieldTable: (json['self_field_table'] as List?)?.cast<int>(),
        disassembly: (json['disassembly'] as List?)?.cast<String>(),
      );

  final String name;
  final int indexInEntries;
  final int offset;
  final int size;
  final String subgraphHash;
  final String opSubgraphHash;
  final String selfHash;
  final List<int> subgraphPp;
  final List<int> selfPp;
  final List<int>? subgraphSelectors;
  final List<int>? selfSelectors;
  final List<int>? subgraphFieldTable;
  final List<int>? selfFieldTable;
  final List<String>? disassembly;

  int get endOffset => offset + size;

  bool containsOffset(int o) => o >= offset && o < endOffset;
}

/// Top-level snapshot summary (matches `SnapshotData` in spec).
class SnapshotData {
  SnapshotData({
    required this.vmDataLength,
    required this.adjustedVmInstructionsLength,
    required this.vmDataHash,
    required this.adjustedVmInstructionsHash,
    this.dartVersion,
    this.snapshotVersion,
  });

  factory SnapshotData.fromJson(Map<String, dynamic> json) => SnapshotData(
        vmDataLength: int.parse(json['vm_data_length'] as String),
        adjustedVmInstructionsLength:
            int.parse(json['adjusted_vm_instructions_length'] as String),
        // Hashes are 64-bit unsigned values written as decimal strings;
        // they routinely exceed signed-int64 max so we keep them as
        // strings and compare by equality only.
        vmDataHash: json['vm_data_hash'] as String,
        adjustedVmInstructionsHash:
            json['adjusted_vm_instructions_hash'] as String,
        dartVersion: json['dart_version'] as String?,
        snapshotVersion: json['snapshot_version'] as String?,
      );

  final int vmDataLength;
  final int adjustedVmInstructionsLength;
  final String vmDataHash;
  final String adjustedVmInstructionsHash;
  final String? dartVersion;
  final String? snapshotVersion;

  /// Are the VM sections of `a` and `b` compatible for patching?
  ///
  /// We require: equal segment lengths, equal `dart_version`, AND equal
  /// *VM-instructions* content hash. The VM snapshot is the core Dart
  /// runtime stubs — it is identical across all builds of a given Dart
  /// version and independent of the app's source, so its hash is the
  /// correct cross-version compatibility invariant (it rejects
  /// cross-Flutter-version patches, the primary failure mode, while
  /// allowing same-version patches that legitimately change app code).
  ///
  /// We deliberately do NOT compare `snapshot_version`: our analyzer
  /// emits it from the ELF **build-id**, which folds in app content and
  /// therefore differs between a base and any genuinely-changed patch —
  /// comparing it for equality would reject every real patch. (The
  /// build-id is a mislabelled "format version"; the VM-instructions
  /// hash above is the app-independent signal it was meant to be.)
  static bool areVmSectionsEqual(SnapshotData a, SnapshotData b) {
    // [sankofa] DIAGNOSTIC ONLY: force-accept to produce a stageable .vmcode for
    // the on-device fusion trace, even when the VM sections are incompatible
    // (e.g. assembly base vs ELF patch). NEVER set this for a real patch — the
    // resulting .vmcode crashes at fused-isolate deserialization.
    if (Platform.environment['SANKOFA_FORCE_LINK'] != null) return true;
    if (a.vmDataLength != b.vmDataLength) return false;
    if (a.adjustedVmInstructionsLength != b.adjustedVmInstructionsLength) {
      return false;
    }
    if (a.dartVersion != b.dartVersion) return false;
    // Compare the VM-instructions content hash. This is the correct
    // compatibility gate: the fusion runs the patch's isolate code against the
    // BASE's VM snapshot, so the two VM images must be byte-identical or the
    // patch's VM-stub references are wrong at runtime. On 2026-06-28 a relaxed
    // (length-only) variant let an iOS `app-aot-assembly` base + `app-aot-elf`
    // patch link despite differing VM bytes — the fused isolate CRASHED on the
    // iPhone (boot 2, no fusion_result written → died in deserialization). So:
    // a hash mismatch is a REAL incompatibility, not a benign backend artifact.
    // The iOS fix is to build the patch sharing the base's VM (linked build /
    // matching backend), NOT to weaken this check. (Build-id `snapshot_version`
    // is app-dependent and unusable here — see git history.)
    if (a.adjustedVmInstructionsHash != b.adjustedVmInstructionsHash) {
      return false;
    }
    return true;
  }

  static Map<String, Object> vmSectionDetails(
    SnapshotData base,
    SnapshotData patch,
  ) {
    return {
      if (patch.dartVersion != null) 'dart_version': patch.dartVersion!,
      if (patch.snapshotVersion != null)
        'snapshot_version': patch.snapshotVersion!,
      'vm_data_length': {
        'base': base.vmDataLength,
        'patch': patch.vmDataLength,
      },
      'vm_instructions_length': {
        'base': base.adjustedVmInstructionsLength,
        'patch': patch.adjustedVmInstructionsLength,
      },
      'vm_data_hash': {
        'base': base.vmDataHash,
        'patch': patch.vmDataHash,
      },
      'vm_instructions_hash': {
        'base': base.adjustedVmInstructionsHash,
        'patch': patch.adjustedVmInstructionsHash,
      },
    };
  }
}

/// Full SnapshotAnalysis result.
class SnapshotAnalysis {
  SnapshotAnalysis({required this.snapshotData, required this.functions});

  factory SnapshotAnalysis.fromJson(Map<String, dynamic> json) =>
      SnapshotAnalysis(
        snapshotData:
            SnapshotData.fromJson(json['snapshot_data'] as Map<String, dynamic>),
        functions: (json['functions'] as List)
            .map((e) => Code.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  factory SnapshotAnalysis.loadFromFile(String path) {
    final raw = File(path).readAsStringSync();
    return SnapshotAnalysis.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  final SnapshotData snapshotData;
  final List<Code> functions;
}
