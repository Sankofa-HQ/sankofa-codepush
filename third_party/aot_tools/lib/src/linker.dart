// Sankofa aot_tools — Linker
//
// Implements the algorithm documented at
// research/aot-tools-decompile/CODEPUSH_SPEC.md §4. Matches patch
// functions to base functions by subgraph_hash, building the
// sim_offset → cpu_offset mapping table the updater uses on device
// to translate patch jumps into base addresses.

import 'dart:typed_data';

import 'snapshot_analysis.dart';

/// A single mapping: this patch function lives at `patch.offset`
/// (sim offset) and replaces the base function at `base.offset`
/// (cpu offset, the address the running app is currently dispatching
/// to).
class Mapping {
  Mapping({required this.base, required this.patch});

  final Code base;
  final Code patch;

  int get cpuOffset => base.offset;
  int get simOffset => patch.offset;
}

class LinkTable {
  LinkTable(this.simToCpu);

  final List<Mapping> simToCpu;

  /// Serialise to the .vmcode prefix format (CODEPUSH_SPEC.md §4):
  ///
  ///   [ count : uint32 BE ]
  ///   [ [ sim_offset : uint32 BE ][ cpu_offset : uint32 BE ] × count ]
  ///   [ zero padding → next `padToAlignment`-byte boundary ]
  Uint8List toBytes({int padToAlignment = 4096}) {
    final builder = BytesBuilder(copy: false);
    void addU32BE(int v) {
      if (v < 0 || v > 0xFFFFFFFF) {
        throw ArgumentError('uint32 out of range: $v');
      }
      final b = ByteData(4)..setUint32(0, v, Endian.big);
      builder.add(b.buffer.asUint8List());
    }

    addU32BE(simToCpu.length);
    for (final m in simToCpu) {
      addU32BE(m.simOffset);
      addU32BE(m.cpuOffset);
    }
    var total = builder.length;
    if (padToAlignment > 0 && total % padToAlignment != 0) {
      final pad = padToAlignment - (total % padToAlignment);
      builder.add(Uint8List(pad));
    }
    return builder.toBytes();
  }
}

/// Hash-group + positional-match linker. Verbatim from CODEPUSH_SPEC.md §4.
class Linker {
  LinkTable link({
    required Iterable<Code> baseCodes,
    required Iterable<Code> patchCodes,
  }) {
    final baseByHash = <String, List<Code>>{};
    for (final c in baseCodes) {
      baseByHash.putIfAbsent(c.subgraphHash, () => []).add(c);
    }
    final patchByHash = <String, List<Code>>{};
    for (final c in patchCodes) {
      patchByHash.putIfAbsent(c.subgraphHash, () => []).add(c);
    }

    final mappings = <Mapping>[];
    for (final entry in patchByHash.entries) {
      final hash = entry.key;
      final patchList = entry.value;
      final baseList = baseByHash[hash];
      if (baseList == null || baseList.isEmpty) {
        // Patch has new functions with no base equivalent — they
        // can't be mapped; the resulting .vmcode includes the full
        // patch code section so the updater can load them as new.
        continue;
      }
      if (patchList.length == baseList.length) {
        for (var i = 0; i < patchList.length; i++) {
          mappings.add(Mapping(base: baseList[i], patch: patchList[i]));
        }
      } else if (patchList.length < baseList.length) {
        for (var i = 0; i < patchList.length; i++) {
          mappings.add(Mapping(base: baseList[i], patch: patchList[i]));
        }
      } else {
        // patchList.length > baseList.length:
        // map first baseList.length pairs, then send any extras to the
        // last base (matches the decompile semantics; the updater
        // dedupes by sim offset).
        for (var i = 0; i < baseList.length; i++) {
          mappings.add(Mapping(base: baseList[i], patch: patchList[i]));
        }
        for (var i = baseList.length; i < patchList.length; i++) {
          mappings.add(Mapping(base: baseList.last, patch: patchList[i]));
        }
      }
    }
    return LinkTable(mappings);
  }
}

int totalCodeSize(Iterable<Code> codes) =>
    codes.fold<int>(0, (sum, c) => sum + c.size);
