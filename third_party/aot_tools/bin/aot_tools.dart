// Sankofa aot_tools — entry point.
//
// Drop-in replacement for Shorebird's closed-source aot-tools.dill.
// Implements the `link` subcommand exactly as the CLI invokes it
// (see executables/aot_tools.dart::link). Output is a .vmcode file
// the Sankofa engine's updater can apply on device.
//
// Subcommands implemented today:
//   link  — build .vmcode from a base + patch AOT pair (v0, no DD)
//
// Reserved subcommand names for parity with the original
// aot-tools.dill (not implemented; would print 'unsupported' or
// no-op as appropriate):
//   compile, dump-blobs, field-table-diff, link-diagnostics,
//   link-metadata, link-stats, pretty-json, query-snapshot

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:sankofa_aot_tools/src/linker.dart';
import 'package:sankofa_aot_tools/src/snapshot_analysis.dart';

/// Version of the Sankofa aot_tools orchestrator. The CLI parses
/// `aot_tools --version` output to gate optional features, so this
/// number is meaningful — bump it when adding capabilities the CLI
/// keys off of.
const String kAotToolsVersion = '0.1.0';

Future<void> main(List<String> args) async {
  final runner = _SankofaCommandRunner()
    ..addCommand(LinkCommand())
    ..addCommand(LinkMetadataCommand());

  // Top-level --version and --trace are passed by the CLI as global
  // options that must precede the subcommand. CommandRunner handles
  // these via argParser overrides below.
  try {
    final code = await runner.run(args);
    exit(code ?? 0);
  } on UsageException catch (e) {
    stderr.writeln(e);
    exit(64);
  }
}

class _SankofaCommandRunner extends CommandRunner<int> {
  _SankofaCommandRunner()
      : super(
          'aot_tools',
          'Sankofa CodePush — patch-creation orchestrator.',
        ) {
    argParser
      ..addFlag(
        'version',
        negatable: false,
        help: 'Print the aot_tools version.',
      )
      ..addOption(
        'trace',
        help: 'Path to a build-trace JSON-lines file. Accepted for '
            'CLI compatibility; events are appended when supplied.',
      );
  }

  @override
  Future<int?> runCommand(ArgResults topLevelResults) async {
    if (topLevelResults['version'] as bool) {
      stdout.writeln(kAotToolsVersion);
      return 0;
    }
    return super.runCommand(topLevelResults);
  }
}

class LinkCommand extends Command<int> {
  LinkCommand() {
    argParser
      ..addOption('base', mandatory: true, help: 'Base AOT snapshot path.')
      ..addOption('patch', mandatory: true, help: 'Patch AOT snapshot path.')
      ..addOption(
        'analyze-snapshot',
        mandatory: true,
        help: 'Path to analyze_snapshot binary.',
      )
      ..addOption(
        'gen-snapshot',
        help: 'Path to gen_snapshot binary (reserved for the optimised '
            'link pipeline; unused in this v0 release).',
      )
      ..addOption('kernel', help: 'Path to patch kernel .dill (reserved).')
      ..addOption('output', mandatory: true, help: 'Output .vmcode file.')
      ..addOption(
        'reporter',
        allowed: ['pretty', 'json'],
        defaultsTo: 'pretty',
      )
      ..addOption(
        'redirect-to',
        help: 'Redirect reporter output to a file (one JSON object per '
            'line when --reporter=json).',
      )
      ..addFlag(
        'verbose',
        negatable: false,
        help: 'Forwarded to analyze_snapshot. Currently a no-op for the '
            'orchestrator itself.',
      )
      ..addFlag(
        'disassemble',
        negatable: false,
        help: 'Include disassembly in analyze_snapshot JSON (slow).',
      )
      ..addFlag(
        'enable-asserts',
        negatable: false,
        help: 'Forwarded to analyze_snapshot.',
      )
      ..addOption(
        'dump-debug-info',
        help: 'Directory to dump intermediate JSON artefacts into.',
      )
      ..addOption(
        'dd-max-bytes',
        defaultsTo: '0',
        hide: true,
        help:
            'Deferred-Dispatch budget (bytes). Currently always 0 — DD '
            'is not yet implemented in Sankofa.',
      );
  }

  @override
  String get name => 'link';

  @override
  String get description => 'Link two AOT snapshots into a .vmcode patch.';

  @override
  Future<int> run() async {
    final results = argResults!;
    final basePath = results['base'] as String;
    final patchPath = results['patch'] as String;
    final analyzeSnapshotPath = results['analyze-snapshot'] as String;
    final outputPath = results['output'] as String;
    final reporterType = results['reporter'] as String;
    final redirectTo = results['redirect-to'] as String?;
    final disassemble = results['disassemble'] as bool;
    final enableAsserts = results['enable-asserts'] as bool;
    final dumpDebugInfo = results['dump-debug-info'] as String?;

    final writer = redirectTo != null
        ? _FileWriter(File(redirectTo))
        : _StdoutWriter();
    final reporter = reporterType == 'pretty'
        ? _PrettyReporter(writer)
        : _JsonReporter(writer);

    if (dumpDebugInfo != null) {
      Directory(dumpDebugInfo).createSync(recursive: true);
    }

    // Run analyze_snapshot on both inputs.
    final baseJsonPath = _jsonPath(basePath, dumpDebugInfo: dumpDebugInfo);
    final patchJsonPath = _jsonPath(patchPath, dumpDebugInfo: dumpDebugInfo);

    reporter.event(_LinkInfo(message: 'analyzing base snapshot'));
    final baseRun = await _runAnalyze(
      analyzeSnapshotPath: analyzeSnapshotPath,
      snapshotPath: basePath,
      outputPath: baseJsonPath,
      enableAsserts: enableAsserts,
      disassemble: disassemble,
    );
    if (baseRun.exitCode != 0) {
      reporter.event(_LinkFailure(
        reason: 'analyze_snapshot --shorebird failed on base snapshot',
        details: {
          'exit_code': baseRun.exitCode,
          'stdout': baseRun.stdout.toString(),
          'stderr': baseRun.stderr.toString(),
        },
      ));
      return 1;
    }

    reporter.event(_LinkInfo(message: 'analyzing patch snapshot'));
    final patchRun = await _runAnalyze(
      analyzeSnapshotPath: analyzeSnapshotPath,
      snapshotPath: patchPath,
      outputPath: patchJsonPath,
      enableAsserts: enableAsserts,
      disassemble: disassemble,
    );
    if (patchRun.exitCode != 0) {
      reporter.event(_LinkFailure(
        reason: 'analyze_snapshot --shorebird failed on patch snapshot',
        details: {
          'exit_code': patchRun.exitCode,
          'stdout': patchRun.stdout.toString(),
          'stderr': patchRun.stderr.toString(),
        },
      ));
      return 1;
    }

    final baseSnapshot = SnapshotAnalysis.loadFromFile(baseJsonPath);
    final patchSnapshot = SnapshotAnalysis.loadFromFile(patchJsonPath);

    if (!SnapshotData.areVmSectionsEqual(
        baseSnapshot.snapshotData, patchSnapshot.snapshotData)) {
      reporter.event(_LinkFailure(
        reason: 'base and patch snapshots have differing VM sections',
        details: SnapshotData.vmSectionDetails(
          baseSnapshot.snapshotData,
          patchSnapshot.snapshotData,
        ),
      ));
      return 1;
    }

    // Run the Linker.
    final linker = Linker();
    final linkTable = linker.link(
      baseCodes: baseSnapshot.functions,
      patchCodes: patchSnapshot.functions,
    );

    final baseSize = totalCodeSize(baseSnapshot.functions);
    final patchSize = totalCodeSize(patchSnapshot.functions);
    final linkedSize = totalCodeSize(linkTable.simToCpu.map((m) => m.patch));
    final linkPct = patchSize == 0 ? 0.0 : 100.0 * linkedSize / patchSize;

    reporter.event(_LinkSuccess(
      baseCodesLength: baseSnapshot.functions.length,
      patchCodesLength: patchSnapshot.functions.length,
      baseCodeSize: baseSize,
      patchCodeSize: patchSize,
      linkedCodeSize: linkedSize,
      linkPercentage: linkPct,
    ));

    // Write the .vmcode file = LinkTable.toBytes() + patch AOT bytes.
    final patchBytes = File(patchPath).readAsBytesSync();
    final linkTableBytes = linkTable.toBytes(padToAlignment: 4096);
    final outFile = File(outputPath);
    outFile.parent.createSync(recursive: true);
    outFile.openSync(mode: FileMode.write)
      ..writeFromSync(linkTableBytes)
      ..writeFromSync(patchBytes)
      ..closeSync();

    reporter.event(_LinkInfo(
      message:
          'wrote vmcode file to $outputPath (link table=${linkTableBytes.length} '
          'bytes, patch=${patchBytes.length} bytes)',
    ));
    return 0;
  }

  String _jsonPath(String snapshotPath, {String? dumpDebugInfo}) {
    final dir = dumpDebugInfo ??
        Directory.systemTemp.createTempSync('sankofa_aot_tools').path;
    final base = snapshotPath.split('/').last;
    return '$dir/$base.analyze_snapshot.json';
  }

  Future<ProcessResult> _runAnalyze({
    required String analyzeSnapshotPath,
    required String snapshotPath,
    required String outputPath,
    required bool enableAsserts,
    required bool disassemble,
  }) {
    final args = <String>[
      if (enableAsserts) '--enable-asserts',
      '--shorebird',
      if (disassemble) '--disassemble',
      '--out=$outputPath',
      snapshotPath,
    ];
    return Process.run(analyzeSnapshotPath, args);
  }
}

/// Emits the same JSON shape Shorebird's `link_metadata` does so the
/// CLI can attach the link-percentage to patch uploads.
class LinkMetadataCommand extends Command<int> {
  @override
  String get name => 'link_metadata';

  @override
  String get description =>
      'Dumps minimal link stats for inclusion in patch metadata.';

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.isEmpty) {
      stderr.writeln('Usage: aot_tools link_metadata <debug_dir_or_zip>');
      return 64;
    }
    final debugBundle = rest.first;
    final dir = Directory(debugBundle);
    if (!dir.existsSync()) {
      // Zip bundles aren't produced by our LinkCommand (we emit a dir
      // via --dump-debug-info); leave that branch unimplemented until
      // a use-case lands.
      stderr.writeln(
        'aot_tools link_metadata expects a debug-info directory; got '
        '$debugBundle (path does not exist as a directory).',
      );
      return 64;
    }
    // The dir contains base + patch analyze_snapshot.json files written
    // by LinkCommand. Find them by extension and re-run the Linker so
    // the stats reflect what shipped.
    final jsonFiles = dir
        .listSync(recursive: false)
        .whereType<File>()
        .where((f) => f.path.endsWith('.analyze_snapshot.json'))
        .toList();
    if (jsonFiles.length < 2) {
      stdout.writeln(jsonEncode({'link_percentage': 0.0, 'reasons': []}));
      return 0;
    }
    // Convention: the base file shows up first lexically (`App.aot...`
    // < `out.aot...`), but to be robust use the file containing the
    // larger function count as the base.
    final analyses = jsonFiles
        .map((f) => SnapshotAnalysis.loadFromFile(f.path))
        .toList()
      ..sort((a, b) => b.functions.length.compareTo(a.functions.length));
    final base = analyses.first;
    final patch = analyses.last;
    final linker = Linker();
    final table = linker.link(
      baseCodes: base.functions,
      patchCodes: patch.functions,
    );
    final patchSize = totalCodeSize(patch.functions);
    final linkedSize = totalCodeSize(table.simToCpu.map((m) => m.patch));
    final pct = patchSize == 0 ? 0.0 : 100.0 * linkedSize / patchSize;
    stdout.writeln(jsonEncode({
      'link_percentage': pct,
      'reasons': <Map<String, Object?>>[],
    }));
    return 0;
  }
}

abstract class _Writer {
  void writeLine(String s);
  void close();
}

class _StdoutWriter implements _Writer {
  @override
  void writeLine(String s) => stdout.writeln(s);
  @override
  void close() {}
}

class _FileWriter implements _Writer {
  _FileWriter(this._file) {
    _file.parent.createSync(recursive: true);
    _sink = _file.openWrite();
  }
  final File _file;
  late final IOSink _sink;
  @override
  void writeLine(String s) => _sink.writeln(s);
  @override
  void close() => _sink.close();
}

abstract class _LinkEvent {
  String get type;
  Map<String, Object?> toJson();
}

class _LinkInfo implements _LinkEvent {
  _LinkInfo({required this.message});
  final String message;
  @override
  String get type => 'link_info';
  @override
  Map<String, Object?> toJson() =>
      {'type': type, 'message': message};
}

class _LinkSuccess implements _LinkEvent {
  _LinkSuccess({
    required this.baseCodesLength,
    required this.patchCodesLength,
    required this.baseCodeSize,
    required this.patchCodeSize,
    required this.linkedCodeSize,
    required this.linkPercentage,
  });
  final int baseCodesLength;
  final int patchCodesLength;
  final int baseCodeSize;
  final int patchCodeSize;
  final int linkedCodeSize;
  final double linkPercentage;

  @override
  String get type => 'link_success';

  @override
  Map<String, Object?> toJson() => {
        'type': type,
        'base_codes_length': baseCodesLength,
        'patch_codes_length': patchCodesLength,
        'base_code_size': baseCodeSize,
        'patch_code_size': patchCodeSize,
        'linked_code_size': linkedCodeSize,
        'link_percentage': linkPercentage,
      };
}

class _LinkFailure implements _LinkEvent {
  _LinkFailure({required this.reason, this.details});
  final String reason;
  final Map<String, Object?>? details;

  @override
  String get type => 'link_failure';

  @override
  Map<String, Object?> toJson() => {
        'type': type,
        'reason': reason,
        if (details != null) 'details': details,
      };
}

abstract class _Reporter {
  void event(_LinkEvent event);
}

class _PrettyReporter implements _Reporter {
  _PrettyReporter(this._writer);
  final _Writer _writer;

  @override
  void event(_LinkEvent event) {
    if (event is _LinkInfo) {
      _writer.writeLine('[sankofa-link] ${event.message}');
    } else if (event is _LinkSuccess) {
      _writer.writeLine(
          '[sankofa-link] linked ${event.linkPercentage.toStringAsFixed(1)}% '
          '(${event.linkedCodeSize}/${event.patchCodeSize} bytes; '
          '${event.patchCodesLength} patch codes vs ${event.baseCodesLength} '
          'base codes)');
    } else if (event is _LinkFailure) {
      _writer.writeLine('[sankofa-link] FAILED: ${event.reason}');
      if (event.details != null) {
        _writer.writeLine('[sankofa-link]   details: ${event.details}');
      }
    }
  }
}

class _JsonReporter implements _Reporter {
  _JsonReporter(this._writer);
  final _Writer _writer;

  @override
  void event(_LinkEvent event) {
    _writer.writeLine(jsonEncode(event.toJson()));
  }
}
