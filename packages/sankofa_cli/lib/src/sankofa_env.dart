import 'dart:io' hide Platform;

import 'package:checked_yaml/checked_yaml.dart';
import 'package:cli_util/cli_util.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:sankofa_cli/src/config/sankofa_yaml.dart';
import 'package:sankofa_cli/src/json_output.dart';
import 'package:sankofa_cli/src/platform.dart';
import 'package:sankofa_cli/src/sankofa_cli_command_runner.dart';
import 'package:sankofa_code_push_client/sankofa_code_push_client.dart';

/// Exception thrown when the Sankofa cache appears to be corrupted.
///
/// Surfaces a user-actionable message directing the user to run
/// `sankofa cache clean` and retry.
class CacheCorruptedException implements Exception {
  /// Creates a [CacheCorruptedException] explaining why the cache is
  /// considered corrupted via [reason] (a complete sentence).
  const CacheCorruptedException(this.reason);

  /// Human-readable explanation of why the cache is considered corrupted.
  final String reason;

  @override
  String toString() =>
      '$reason Your Sankofa installation may be corrupted. '
      "Try running 'sankofa cache clean' and retrying.";
}

/// A reference to a [SankofaEnv] instance.
final sankofaEnvRef = create(SankofaEnv.new);

/// The [SankofaEnv] instance available in the current zone.
SankofaEnv get sankofaEnv => read(sankofaEnvRef);

/// {@template sankofa_env}
/// A class that provides access to sankofa environment metadata.
/// {@endtemplate}
class SankofaEnv {
  /// {@macro sankofa_env}
  const SankofaEnv({
    String? flutterRevisionOverride,
    String? flutterProjectRootOverride,
  }) : _flutterRevisionOverride = flutterRevisionOverride,
       _flutterProjectRootOverride = flutterProjectRootOverride;

  /// Copy the [SankofaEnv] and optionally override the flutter revision.
  SankofaEnv copyWith({String? flutterRevisionOverride}) => SankofaEnv(
    flutterRevisionOverride:
        flutterRevisionOverride ?? _flutterRevisionOverride,
  );

  final String? _flutterRevisionOverride;
  final String? _flutterProjectRootOverride;

  /// The application config directory for the Sankofa CLI.
  Directory get configDirectory {
    return Directory(applicationConfigHome(executableName));
  }

  /// The directory where sankofa logs are stored.
  Directory get logsDirectory {
    return Directory(p.join(configDirectory.path, 'logs'));
  }

  /// The root directory of the Sankofa install.
  ///
  /// Assumes we are running from $ROOT/bin/cache.
  Directory get sankofaRoot {
    return File(platform.script.toFilePath()).parent.parent.parent;
  }

  /// The Sankofa engine revision.
  String get sankofaEngineRevision {
    final file = File(
      p.join(flutterDirectory.path, 'bin', 'internal', 'engine.version'),
    );
    try {
      return file.readAsStringSync().trim();
    } on FileSystemException {
      throw CacheCorruptedException('Could not read ${file.path}.');
    }
  }

  /// Get the Sankofa Flutter revision.
  String get flutterRevision {
    if (_flutterRevisionOverride != null) return _flutterRevisionOverride;
    final file = File(
      p.join(sankofaRoot.path, 'bin', 'internal', 'flutter.version'),
    );
    try {
      return file.readAsStringSync().trim();
    } on FileSystemException {
      throw CacheCorruptedException('Could not read ${file.path}.');
    }
  }

  /// Whether the project uses package:sankofa_code_push.
  bool get usesSankofaCodePushPackage {
    final pubspec = getPubspecYaml();
    return pubspec?.dependencies.containsKey('sankofa_code_push') ?? false;
  }

  /// The root of the Sankofa-vended Flutter git checkout.
  Directory get flutterDirectory {
    return Directory(
      p.join(sankofaRoot.path, 'bin', 'cache', 'flutter', flutterRevision),
    );
  }

  /// The Sankofa-vended Flutter binary.
  File get flutterBinaryFile {
    final flutter = platform.isWindows ? 'flutter.bat' : 'flutter';
    return File(p.join(flutterDirectory.path, 'bin', flutter));
  }

  /// The Sankofa-vended Dart binary.
  File get dartBinaryFile {
    final dart = platform.isWindows ? 'dart.bat' : 'dart';
    return File(p.join(flutterDirectory.path, 'bin', dart));
  }

  /// The Cocoapods lockfile for this project's iOS app.
  File get iosPodfileLockFile {
    return File(p.join(getFlutterProjectRoot()!.path, 'ios', 'Podfile.lock'));
  }

  /// The hash of the Podfile.lock file for this project's iOS app. Will be null
  /// if the file does not exist.
  String? get iosPodfileLockHash {
    if (!iosPodfileLockFile.existsSync()) return null;
    return sha256.convert(iosPodfileLockFile.readAsBytesSync()).toString();
  }

  /// The Cocoapods lockfile for this project's macOS app.
  File get macosPodfileLockFile {
    return File(p.join(getFlutterProjectRoot()!.path, 'macos', 'Podfile.lock'));
  }

  /// The hash of the Podfile.lock file for this project's macOS app. Will be
  /// null if the file does not exist.
  String? get macosPodfileLockHash {
    if (!macosPodfileLockFile.existsSync()) return null;
    return sha256.convert(macosPodfileLockFile.readAsBytesSync()).toString();
  }

  /// The build directory of the current sankofa project.
  Directory get buildDirectory {
    return Directory(p.join(getFlutterProjectRoot()!.path, 'build'));
  }

  /// Where the link supplement files are stored.
  // TODO(eseidel): Make this not iOS specific.
  // Sankofa-built engine's gen_snapshot writes patch link metadata
  // (App.ct.link / App.ft.link / App.dt.link) into build/ios/sankofa once
  // Phase 1 codepush patches land. Mirrors the same path in
  // ArtifactManager.getReleaseSupplementDirectory.
  Directory get iosSupplementDirectory =>
      Directory(p.join(buildDirectory.path, 'ios', 'sankofa'));

  /// The `sankofa.yaml` file for this project.
  File getSankofaYamlFile({required Directory cwd}) {
    return File(p.join(cwd.path, 'sankofa.yaml'));
  }

  /// The `pubspec.yaml` file for this project.
  File getPubspecYamlFile({required Directory cwd}) {
    return File(p.join(cwd.path, 'pubspec.yaml'));
  }

  /// Finds nearest ancestor file
  /// relative to the [cwd] that satisfies [where].
  File? findNearestAncestor({
    required File? Function(String path) where,
    Directory? cwd,
  }) {
    Directory? prev;
    var dir = cwd ?? Directory.current;
    while (prev?.path != dir.path) {
      final file = where(dir.path);
      if (file?.existsSync() ?? false) return file;
      prev = dir;
      dir = dir.parent;
    }
    return null;
  }

  /// Returns the root directory of the nearest Sankofa project.
  Directory? getSankofaProjectRoot() {
    final file = findNearestAncestor(
      where: (path) => getSankofaYamlFile(cwd: Directory(path)),
    );
    if (file == null || !file.existsSync()) return null;
    return Directory(p.dirname(file.path));
  }

  /// Returns the root directory of the nearest Flutter project.
  Directory? getFlutterProjectRoot() {
    if (_flutterProjectRootOverride != null) {
      return Directory(_flutterProjectRootOverride);
    }
    final file = findNearestAncestor(
      where: (path) => getPubspecYamlFile(cwd: Directory(path)),
    );
    if (file == null || !file.existsSync()) return null;
    return Directory(p.dirname(file.path));
  }

  /// The `sankofa.yaml` file for this project, parsed into a [SankofaYaml]
  /// object.
  ///
  /// Returns `null` if the file does not exist.
  /// Throws a [ParsedYamlException] if the file exists but is invalid.
  SankofaYaml? getSankofaYaml() {
    final root = getSankofaProjectRoot();
    if (root == null) return null;
    final yaml = getSankofaYamlFile(cwd: root).readAsStringSync();
    return checkedYamlDecode(yaml, (m) => SankofaYaml.fromJson(m!));
  }

  /// The `pubspec.yaml` file for this project, parsed into a [Pubspec] object.
  ///
  /// Returns `null` if the file does not exist.
  /// Throws a [ParsedYamlException] if the file exists but is invalid.
  Pubspec? getPubspecYaml() {
    final root = getFlutterProjectRoot();
    if (root == null) return null;
    try {
      final yaml = getPubspecYamlFile(cwd: root).readAsStringSync();
      return Pubspec.parse(yaml, lenient: true);
    } on Exception {
      return null;
    }
  }

  /// No-op: the Sankofa-built Flutter engine reads `sankofa.yaml` directly,
  /// so we no longer need to generate a side-by-side `shorebird.yaml` copy.
  ///
  /// Kept as an empty method so existing call sites don't break; remove the
  /// method and its calls in a follow-up refactor.
  void syncEngineConfigYaml() {
    // Intentionally empty. See doc comment.
  }

  /// Whether the current project has a `sankofa.yaml` file.
  bool get hasSankofaYaml => getSankofaYaml() != null;

  /// Whether the current project has a `pubspec.yaml` file.
  bool get hasPubspecYaml => getPubspecYaml() != null;

  /// Whether the current project's `pubspec.yaml` file contains a reference to
  /// `sankofa.yaml` in its `assets` section.
  bool get pubspecContainsSankofaYaml {
    final pubspec = getPubspecYaml();
    if (pubspec == null) return false;
    if (pubspec.flutter == null) return false;
    if (pubspec.flutter!['assets'] == null) return false;
    final assets = pubspec.flutter!['assets'] as List;
    return assets.contains('sankofa.yaml');
  }

  /// Returns the Android package name from the pubspec.yaml file of a Flutter
  /// module.
  String? get androidPackageName {
    final pubspec = getPubspecYaml();
    final module = pubspec?.flutter?['module'] as Map?;
    return module?['androidPackage'] as String?;
  }

  /// The base URL for the Sankofa auth service. Can be overridden with the
  /// `AUTH_SERVICE_URL` environment variable. Defaults to
  /// `https://auth.sankofa.dev`.
  Uri get authServiceUri => Uri.parse(
    platform.environment['AUTH_SERVICE_URL'] ?? 'https://auth.sankofa.dev',
  );

  /// The expected JWT issuer for Sankofa-issued tokens. Can be overridden
  /// with the `SANKOFA_JWT_ISSUER` environment variable. Defaults to
  /// `https://auth.sankofa.dev`.
  String get jwtIssuer =>
      platform.environment['SANKOFA_JWT_ISSUER'] ??
      'https://auth.sankofa.dev';

  /// The base URL for the Sankofa code push server that overrides the default
  /// used by [CodePushClient]. If none is provided, [CodePushClient] will use
  /// its default.
  Uri? get hostedUri {
    try {
      final baseUrl =
          platform.environment['SANKOFA_HOSTED_URL'] ??
          getSankofaYaml()?.baseUrl;
      return baseUrl == null ? null : Uri.tryParse(baseUrl);
    } on Exception {
      return null;
    }
  }

  /// Whether the CLI can accept user input via stdin.
  ///
  /// Returns `false` when stdin is not a terminal, when running on CI, or
  /// when the user has opted into non-interactive output via `--json`.
  bool get canAcceptUserInput =>
      stdin.hasTerminal && !isRunningOnCI && !isJsonMode;

  /// Whether platform.environment indicates that we are running on a CI
  /// platform. This implementation is intended to behave similar to the Flutter
  /// tool's:
  /// https://github.com/flutter/flutter/blob/0c10e1ca54ae74043909059e2ff56bf5dd0c3d23/packages/flutter_tools/lib/src/base/bot_detector.dart#L48-L69
  bool get isRunningOnCI =>
      platform.environment['BOT'] == 'true'
      // https://docs.travis-ci.com/user/environment-variables/#Default-Environment-Variables
      ||
      platform.environment['TRAVIS'] == 'true' ||
      platform.environment['CONTINUOUS_INTEGRATION'] == 'true' ||
      platform.environment.containsKey('CI') // Travis and AppVeyor
      // https://www.appveyor.com/docs/environment-variables/
      ||
      platform.environment.containsKey('APPVEYOR')
      // https://cirrus-ci.org/guide/writing-tasks/#environment-variables
      ||
      platform.environment.containsKey('CIRRUS_CI')
      // https://docs.aws.amazon.com/codebuild/latest/userguide/build-env-ref-env-vars.html
      ||
      (platform.environment.containsKey('AWS_REGION') &&
          platform.environment.containsKey('CODEBUILD_INITIATOR'))
      // https://wiki.jenkins.io/display/JENKINS/Building+a+software+project#Buildingasoftwareproject-belowJenkinsSetEnvironmentVariables
      ||
      platform.environment.containsKey('JENKINS_URL')
      // https://help.github.com/en/actions/configuring-and-managing-workflows/using-environment-variables#default-environment-variables
      ||
      platform.environment.containsKey('GITHUB_ACTIONS')
      // https://learn.microsoft.com/en-us/azure/devops/pipelines/build/variables?view=azure-devops&tabs=yaml
      ||
      platform.environment.containsKey('TF_BUILD');
}
