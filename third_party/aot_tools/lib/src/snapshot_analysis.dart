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
        vmDataHash: int.parse(json['vm_data_hash'] as String),
        adjustedVmInstructionsHash:
            int.parse(json['adjusted_vm_instructions_hash'] as String),
        dartVersion: json['dart_version'] as String?,
        snapshotVersion: json['snapshot_version'] as String?,
      );

  final int vmDataLength;
  final int adjustedVmInstructionsLength;
  final int vmDataHash;
  final int adjustedVmInstructionsHash;
  final String? dartVersion;
  final String? snapshotVersion;

  /// Are the VM sections of `a` and `b` byte-for-byte equivalent?
  /// The Linker rejects patches whose base and patch VM sections
  /// differ — they were compiled with different kernels/flags.
  static bool areVmSectionsEqual(SnapshotData a, SnapshotData b) =>
      a.vmDataLength == b.vmDataLength &&
      a.adjustedVmInstructionsLength == b.adjustedVmInstructionsLength &&
      a.vmDataHash == b.vmDataHash &&
      a.adjustedVmInstructionsHash == b.adjustedVmInstructionsHash;

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
