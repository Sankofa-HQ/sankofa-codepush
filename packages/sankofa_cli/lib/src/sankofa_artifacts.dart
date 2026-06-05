// Allowing one member abstracts for consistency/namespace/ease of testing.
// ignore_for_file: one_member_abstracts

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:sankofa_cli/src/cache.dart';
import 'package:sankofa_cli/src/engine_config.dart';
import 'package:sankofa_cli/src/sankofa_env.dart';

/// All Sankofa artifacts used explicitly by Sankofa.
enum SankofaArtifact {
  /// The iOS analyze_snapshot executable.
  analyzeSnapshotIos,

  /// The macOS analyze_snapshot executable.
  analyzeSnapshotMacOS,

  /// The aot_tools executable or kernel file.
  aotTools,

  /// The gen_snapshot executable for iOS.
  genSnapshotIos,

  /// The gen_snapshot executable for macOS that creates arm64 snapshots.
  genSnapshotMacosArm64,

  /// The gen_snapshot executable for macOS that creates x64 snapshots.
  genSnapshotMacosX64,
}

/// A reference to a [SankofaArtifacts] instance.
final sankofaArtifactsRef = create<SankofaArtifacts>(
  SankofaCachedArtifacts.new,
);

/// The [SankofaArtifacts] instance available in the current zone.
SankofaArtifacts get sankofaArtifacts => read(sankofaArtifactsRef);

/// {@template sankofa_artifacts}
/// A class that provides access to Sankofa artifacts.
/// {@endtemplate}
abstract class SankofaArtifacts {
  /// Returns the path to the given [artifact].
  String getArtifactPath({required SankofaArtifact artifact});
}

/// {@template sankofa_cached_artifacts}
/// A class that provides access to cached Sankofa artifacts.
/// {@endtemplate}
class SankofaCachedArtifacts implements SankofaArtifacts {
  /// {@macro sankofa_cached_artifacts}
  const SankofaCachedArtifacts();

  @override
  String getArtifactPath({required SankofaArtifact artifact}) {
    switch (artifact) {
      case SankofaArtifact.analyzeSnapshotIos:
        return _analyzeSnapshotIosFile.path;
      case SankofaArtifact.analyzeSnapshotMacOS:
        return _analyzeSnapshotMacosFile.path;
      case SankofaArtifact.aotTools:
        return _aotToolsFile.path;
      case SankofaArtifact.genSnapshotIos:
        return _genSnapshotIosFile.path;
      case SankofaArtifact.genSnapshotMacosArm64:
        return _genSnapshotMacOsArm64File.path;
      case SankofaArtifact.genSnapshotMacosX64:
        return _genSnapshotMacOsX64File.path;
    }
  }

  File get _analyzeSnapshotIosFile {
    return File(
      p.join(
        sankofaEnv.flutterDirectory.path,
        'bin',
        'cache',
        'artifacts',
        'engine',
        'ios-release',
        'analyze_snapshot_arm64',
      ),
    );
  }

  File get _analyzeSnapshotMacosFile {
    return File(
      p.join(
        sankofaEnv.flutterDirectory.path,
        'bin',
        'cache',
        'artifacts',
        'engine',
        'darwin-x64-release',
        'analyze_snapshot',
      ),
    );
  }

  /// Resolves the bundled Sankofa `aot_tools` Dart entry point.
  ///
  /// Sankofa CodePush ships its own orchestrator (a drop-in replacement
  /// for Shorebird's closed `aot-tools.dill`) at
  /// `third_party/aot_tools/bin/aot_tools.dart` under the repo root.
  /// The executable wrapper detects the `.dart` extension and invokes
  /// it via `dart run`.
  File get _aotToolsFile {
    return File(
      p.join(
        sankofaEnv.sankofaRoot.path,
        'third_party',
        'aot_tools',
        'bin',
        'aot_tools.dart',
      ),
    );
  }

  File get _genSnapshotIosFile {
    return File(
      p.join(
        sankofaEnv.flutterDirectory.path,
        'bin',
        'cache',
        'artifacts',
        'engine',
        'ios-release',
        'gen_snapshot_arm64',
      ),
    );
  }

  File get _genSnapshotMacOsArm64File {
    return File(
      p.join(
        sankofaEnv.flutterDirectory.path,
        'bin',
        'cache',
        'artifacts',
        'engine',
        'darwin-x64-release',
        'gen_snapshot_arm64',
      ),
    );
  }

  File get _genSnapshotMacOsX64File {
    return File(
      p.join(
        sankofaEnv.flutterDirectory.path,
        'bin',
        'cache',
        'artifacts',
        'engine',
        'darwin-x64-release',
        'gen_snapshot_x64',
      ),
    );
  }
}

/// {@template sankofa_local_engine_artifacts}
/// A class that provides access to locally built Sankofa artifacts.
/// {@endtemplate}
class SankofaLocalEngineArtifacts implements SankofaArtifacts {
  /// {@macro sankofa_local_engine_artifacts}
  const SankofaLocalEngineArtifacts();

  @override
  String getArtifactPath({required SankofaArtifact artifact}) {
    switch (artifact) {
      case SankofaArtifact.analyzeSnapshotIos:
        return _analyzeSnapshotIosFile.path;
      case SankofaArtifact.analyzeSnapshotMacOS:
        return _analyzeSnapshotMacosFile.path;
      case SankofaArtifact.aotTools:
        return _aotToolsFile.path;
      case SankofaArtifact.genSnapshotIos:
        return _genSnapshotIosFile.path;
      case SankofaArtifact.genSnapshotMacosArm64:
        return _genSnapshotMacosArm64File.path;
      case SankofaArtifact.genSnapshotMacosX64:
        return _genSnapshotMacosX64File.path;
    }
  }

  File get _analyzeSnapshotIosFile {
    return File(
      p.join(
        engineConfig.localEngineSrcPath!,
        'out',
        engineConfig.localEngine,
        'clang_x64',
        'analyze_snapshot_arm64',
      ),
    );
  }

  File get _analyzeSnapshotMacosFile {
    return File(
      p.join(
        engineConfig.localEngineSrcPath!,
        'out',
        engineConfig.localEngine,
        'clang_x64',
        'analyze_snapshot',
      ),
    );
  }

  File get _aotToolsFile {
    return File(
      p.join(
        engineConfig.localEngineSrcPath!,
        'flutter',
        'third_party',
        'dart',
        'pkg',
        'aot_tools',
        'bin',
        'aot_tools.dart',
      ),
    );
  }

  File get _genSnapshotIosFile {
    return File(
      p.join(
        engineConfig.localEngineSrcPath!,
        'out',
        engineConfig.localEngine,
        'clang_x64',
        'gen_snapshot_arm64',
      ),
    );
  }

  File get _genSnapshotMacosArm64File {
    return File(
      p.join(
        engineConfig.localEngineSrcPath!,
        'out',
        engineConfig.localEngine,
        'artifacts_arm64',
        'gen_snapshot',
      ),
    );
  }

  File get _genSnapshotMacosX64File {
    return File(
      p.join(
        engineConfig.localEngineSrcPath!,
        'out',
        engineConfig.localEngine,
        'artifacts_x64',
        'gen_snapshot',
      ),
    );
  }
}
