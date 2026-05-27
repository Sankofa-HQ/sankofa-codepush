import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:sankofa_cli/src/json_output.dart';
import 'package:sankofa_cli/src/platform.dart';
import 'package:sankofa_cli/src/sankofa_cli_command_runner.dart';
import 'package:sankofa_cli/src/sankofa_env.dart';
import 'package:test/test.dart';

import 'mocks.dart';

void main() {
  group(SankofaEnv, () {
    const flutterRevision = 'test-flutter-revision';
    late Platform platform;
    late Directory sankofaRoot;
    late Uri platformScript;
    late SankofaEnv sankofaEnv;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {
          platformRef.overrideWith(() => platform),
          isJsonModeRef.overrideWith(() => false),
        },
      );
    }

    setUp(() {
      sankofaRoot = Directory.systemTemp.createTempSync();
      platformScript = Uri.file(
        p.join(sankofaRoot.path, 'bin', 'cache', 'sankofa.snapshot'),
      );
      File(p.join(sankofaRoot.path, 'bin', 'internal', 'flutter.version'))
        ..createSync(recursive: true)
        ..writeAsStringSync(flutterRevision, flush: true);
      platform = MockPlatform();
      sankofaEnv = runWithOverrides(SankofaEnv.new);

      when(() => platform.environment).thenReturn(const {});
      when(() => platform.script).thenReturn(platformScript);
    });

    group('copyWith', () {
      test('creates a new instance with the provided values', () {
        final newEnv = runWithOverrides(
          () => sankofaEnv.copyWith(flutterRevisionOverride: 'test'),
        );
        expect(newEnv, isNot(same(sankofaEnv)));
        expect(newEnv.flutterRevision, equals('test'));
      });

      test('uses existing values when not provided', () {
        final newEnv = runWithOverrides(() => sankofaEnv.copyWith());
        expect(newEnv, isNot(same(sankofaEnv)));
        expect(
          runWithOverrides(() => newEnv.flutterRevision),
          equals(flutterRevision),
        );
      });
    });

    group('configDirectory', () {
      test('returns correct directory', () {
        expect(
          runWithOverrides(() => sankofaEnv.configDirectory.path),
          endsWith(executableName),
        );
      });
    });

    group('logsDirectory', () {
      test('returns correct directory', () {
        expect(
          runWithOverrides(() => sankofaEnv.logsDirectory.path),
          endsWith(p.join(executableName, 'logs')),
        );
      });
    });

    group('getSankofaYamlFile', () {
      test('returns correct file', () {
        final tempDir = Directory.systemTemp.createTempSync();
        expect(
          runWithOverrides(
            () => sankofaEnv.getSankofaYamlFile(cwd: tempDir).path,
          ),
          equals(p.join(tempDir.path, 'sankofa.yaml')),
        );
      });
    });

    group('getFlutterProjectRoot', () {
      test('uses override when provided', () {
        final tempDir = Directory.systemTemp.createTempSync();
        final overridePubspec = File(
          p.join(tempDir.path, 'override', 'pubspec.yaml'),
        );
        final override = overridePubspec.parent.path;
        File(p.join(tempDir.path, 'pubspec.yaml')).createSync(recursive: true);
        expect(
          runWithOverrides(
            () => SankofaEnv(
              flutterProjectRootOverride: override,
            ).getFlutterProjectRoot(),
          ),
          isA<Directory>().having((d) => d.path, 'absolute', override),
        );
      });

      test('returns null when no Flutter project exists', () {
        final tempDir = Directory.systemTemp.createTempSync();
        expect(
          IOOverrides.runZoned(
            () => runWithOverrides(() => sankofaEnv.getFlutterProjectRoot()),
            getCurrentDirectory: () => tempDir,
          ),
          isNull,
        );
      });

      test('returns correct directory when Flutter project exists (root)', () {
        final tempDir = Directory.systemTemp.createTempSync();
        File(p.join(tempDir.path, 'pubspec.yaml')).createSync(recursive: true);
        final projectRoot = IOOverrides.runZoned(
          () => runWithOverrides(() => sankofaEnv.getFlutterProjectRoot()),
          getCurrentDirectory: () => tempDir,
        );
        expect(projectRoot!.path, equals(tempDir.path));
      });

      test(
        'returns correct directory when Flutter project exists (nested)',
        () {
          final tempDir = Directory.systemTemp.createTempSync();
          final nestedDir = Directory(p.join(tempDir.path, 'nested'));
          File(
            p.join(tempDir.path, 'pubspec.yaml'),
          ).createSync(recursive: true);
          final projectRoot = IOOverrides.runZoned(
            () => runWithOverrides(() => sankofaEnv.getFlutterProjectRoot()),
            getCurrentDirectory: () => nestedDir,
          );
          expect(projectRoot!.path, equals(tempDir.path));
        },
      );
    });

    group('getSankofaProjectRoot', () {
      test('returns null when no Sankofa project exists', () {
        final tempDir = Directory.systemTemp.createTempSync();
        expect(
          IOOverrides.runZoned(
            () =>
                runWithOverrides(() => sankofaEnv.getSankofaProjectRoot()),
            getCurrentDirectory: () => tempDir,
          ),
          isNull,
        );
      });

      test(
        'returns correct directory when Sankofa project exists (root)',
        () {
          final tempDir = Directory.systemTemp.createTempSync();
          File(
            p.join(tempDir.path, 'sankofa.yaml'),
          ).createSync(recursive: true);
          final projectRoot = IOOverrides.runZoned(
            () =>
                runWithOverrides(() => sankofaEnv.getSankofaProjectRoot()),
            getCurrentDirectory: () => tempDir,
          );
          expect(projectRoot!.path, equals(tempDir.path));
        },
      );

      test(
        'returns correct directory when Flutter project exists (nested)',
        () {
          final tempDir = Directory.systemTemp.createTempSync();
          final nestedDir = Directory(p.join(tempDir.path, 'nested'));
          File(
            p.join(tempDir.path, 'sankofa.yaml'),
          ).createSync(recursive: true);
          final projectRoot = IOOverrides.runZoned(
            () =>
                runWithOverrides(() => sankofaEnv.getSankofaProjectRoot()),
            getCurrentDirectory: () => nestedDir,
          );
          expect(projectRoot!.path, equals(tempDir.path));
        },
      );
    });

    group('dartBinaryFile', () {
      test('returns correct path', () {
        when(() => platform.isWindows).thenReturn(false);
        expect(
          runWithOverrides(() => sankofaEnv.dartBinaryFile.path),
          equals(
            p.join(
              sankofaRoot.path,
              'bin',
              'cache',
              'flutter',
              flutterRevision,
              'bin',
              'dart',
            ),
          ),
        );
        when(() => platform.isWindows).thenReturn(true);
        expect(
          runWithOverrides(() => sankofaEnv.dartBinaryFile.path),
          equals(
            p.join(
              sankofaRoot.path,
              'bin',
              'cache',
              'flutter',
              flutterRevision,
              'bin',
              'dart.bat',
            ),
          ),
        );
      });
    });

    group('iosPodfileLockFile', () {
      test('returns correct path', () {
        final tempDir = Directory.systemTemp.createTempSync();
        File(p.join(tempDir.path, 'pubspec.yaml')).createSync(recursive: true);
        final podfileLockFile = IOOverrides.runZoned(
          () => runWithOverrides(() => sankofaEnv.iosPodfileLockFile),
          getCurrentDirectory: () => tempDir,
        );
        expect(
          podfileLockFile.path,
          equals(p.join(tempDir.path, 'ios', 'Podfile.lock')),
        );
      });
    });

    group('iosPodfileLockHash', () {
      group('when file does not exist', () {
        test('returns null', () {
          expect(
            runWithOverrides(() => sankofaEnv.iosPodfileLockHash),
            isNull,
          );
        });
      });

      group('when file exists', () {
        late Directory tempDir;
        late String podfileLockHash;

        setUp(() {
          tempDir = Directory.systemTemp.createTempSync();

          // Required to resolve the project root.
          File(
            p.join(tempDir.path, 'pubspec.yaml'),
          ).createSync(recursive: true);

          const podfileLockContents = 'lock file';
          podfileLockHash = sha256
              .convert(utf8.encode(podfileLockContents))
              .toString();
          File(p.join(tempDir.path, 'ios', 'Podfile.lock'))
            ..createSync(recursive: true)
            ..writeAsStringSync(podfileLockContents);
        });

        test('returns correct hash', () {
          final actualHash = IOOverrides.runZoned(
            () => runWithOverrides(() => sankofaEnv.iosPodfileLockHash),
            getCurrentDirectory: () => tempDir,
          );
          expect(actualHash, equals(podfileLockHash));
        });
      });
    });

    group('buildDirectory', () {
      test('returns correct path', () {
        final tempDir = Directory.systemTemp.createTempSync();
        File(p.join(tempDir.path, 'pubspec.yaml')).createSync(recursive: true);
        Directory(p.join(tempDir.path, 'build')).createSync(recursive: true);
        final buildDirectory = IOOverrides.runZoned(
          () => runWithOverrides(() => sankofaEnv.buildDirectory),
          getCurrentDirectory: () => tempDir,
        );
        expect(buildDirectory.path, equals(p.join(tempDir.path, 'build')));
      });
    });

    group('iosSupplementDirectory', () {
      test('returns correct path', () {
        final tempDir = Directory.systemTemp.createTempSync();
        File(p.join(tempDir.path, 'pubspec.yaml')).createSync(recursive: true);
        Directory(
          p.join(tempDir.path, 'build', 'ios', 'sankofa'),
        ).createSync(recursive: true);
        final supplementDirectory = IOOverrides.runZoned(
          () => runWithOverrides(() => sankofaEnv.iosSupplementDirectory),
          getCurrentDirectory: () => tempDir,
        );
        expect(
          supplementDirectory.path,
          equals(p.join(tempDir.path, 'build', 'ios', 'sankofa')),
        );
      });
    });

    group('macosPodfileLockFile', () {
      test('returns correct path', () {
        final tempDir = Directory.systemTemp.createTempSync();
        File(p.join(tempDir.path, 'pubspec.yaml')).createSync(recursive: true);
        final podfileLockFile = IOOverrides.runZoned(
          () => runWithOverrides(() => sankofaEnv.macosPodfileLockFile),
          getCurrentDirectory: () => tempDir,
        );
        expect(
          podfileLockFile.path,
          equals(p.join(tempDir.path, 'macos', 'Podfile.lock')),
        );
      });
    });

    group('macosPodfileLockHash', () {
      group('when file does not exist', () {
        test('returns null', () {
          expect(
            runWithOverrides(() => sankofaEnv.macosPodfileLockHash),
            isNull,
          );
        });
      });

      group('when file exists', () {
        late Directory tempDir;
        late String podfileLockHash;

        setUp(() {
          tempDir = Directory.systemTemp.createTempSync();

          // Required to resolve the project root.
          File(
            p.join(tempDir.path, 'pubspec.yaml'),
          ).createSync(recursive: true);

          const podfileLockContents = 'lock file';
          podfileLockHash = sha256
              .convert(utf8.encode(podfileLockContents))
              .toString();
          File(p.join(tempDir.path, 'macos', 'Podfile.lock'))
            ..createSync(recursive: true)
            ..writeAsStringSync(podfileLockContents);
        });

        test('returns correct hash', () {
          final actualHash = IOOverrides.runZoned(
            () => runWithOverrides(() => sankofaEnv.macosPodfileLockHash),
            getCurrentDirectory: () => tempDir,
          );
          expect(actualHash, equals(podfileLockHash));
        });
      });
    });

    group('flutterBinaryFile', () {
      test('returns correct path', () {
        when(() => platform.isWindows).thenReturn(false);
        expect(
          runWithOverrides(() => sankofaEnv.flutterBinaryFile.path),
          equals(
            p.join(
              sankofaRoot.path,
              'bin',
              'cache',
              'flutter',
              flutterRevision,
              'bin',
              'flutter',
            ),
          ),
        );
        when(() => platform.isWindows).thenReturn(true);
        expect(
          runWithOverrides(() => sankofaEnv.flutterBinaryFile.path),
          equals(
            p.join(
              sankofaRoot.path,
              'bin',
              'cache',
              'flutter',
              flutterRevision,
              'bin',
              'flutter.bat',
            ),
          ),
        );
      });
    });

    group('getPubspecYamlFile', () {
      test('returns correct file', () {
        final tempDir = Directory.systemTemp.createTempSync();
        expect(
          runWithOverrides(
            () => sankofaEnv.getPubspecYamlFile(cwd: tempDir).path,
          ),
          equals(p.join(tempDir.path, 'pubspec.yaml')),
        );
      });
    });

    group('getPubspecYaml', () {
      test('returns null when pubspec.yaml does not exist', () {
        final tempDir = Directory.systemTemp.createTempSync();
        expect(
          IOOverrides.runZoned(
            () => runWithOverrides(() => sankofaEnv.getPubspecYaml()),
            getCurrentDirectory: () => tempDir,
          ),
          isNull,
        );
      });

      test('returns null when error occurs reading pubspec.yaml', () {
        final tempDir = Directory.systemTemp.createTempSync();
        // This is not valid utf8 so readAsString will throw.
        File(
          p.join(tempDir.path, 'pubspec.yaml'),
        ).writeAsBytesSync([999999999999]);
        expect(
          IOOverrides.runZoned(
            () => runWithOverrides(() => sankofaEnv.getPubspecYaml()),
            getCurrentDirectory: () => tempDir,
          ),
          isNull,
        );
      });

      test('returns value when pubspec.yaml exists', () {
        final tempDir = Directory.systemTemp.createTempSync();
        File(
          p.join(tempDir.path, 'pubspec.yaml'),
        ).writeAsStringSync('name: test');
        expect(
          IOOverrides.runZoned(
            () => runWithOverrides(() => sankofaEnv.getPubspecYaml()),
            getCurrentDirectory: () => tempDir,
          ),
          isA<Pubspec>().having((p) => p.name, 'name', 'test'),
        );
      });

      test('returns value when pubspec.yaml exists '
          'and contains a malformed value', () {
        final tempDir = Directory.systemTemp.createTempSync();
        File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: test
publish_to: yon30c
        ''');
        expect(
          IOOverrides.runZoned(
            () => runWithOverrides(() => sankofaEnv.getPubspecYaml()),
            getCurrentDirectory: () => tempDir,
          ),
          isA<Pubspec>()
              .having((p) => p.name, 'name', 'test')
              .having((p) => p.publishTo, 'publishTo', isNull),
        );
      });
    });

    group('hasPubspecYaml', () {
      test('returns false when pubspec.yaml does not exist', () {
        final tempDir = Directory.systemTemp.createTempSync();
        expect(
          IOOverrides.runZoned(
            () => runWithOverrides(() => sankofaEnv.hasPubspecYaml),
            getCurrentDirectory: () => tempDir,
          ),
          isFalse,
        );
      });

      test('returns true when pubspec.yaml does exist', () {
        final tempDir = Directory.systemTemp.createTempSync();
        File(
          p.join(tempDir.path, 'pubspec.yaml'),
        ).writeAsStringSync('name: test');
        expect(
          IOOverrides.runZoned(
            () => runWithOverrides(() => sankofaEnv.hasPubspecYaml),
            getCurrentDirectory: () => tempDir,
          ),
          isTrue,
        );
      });

      test('returns true even if pubspec.yaml contains malformed values', () {
        final tempDir = Directory.systemTemp.createTempSync();
        File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: test
publish_to: yon30c
        ''');
        expect(
          IOOverrides.runZoned(
            () => runWithOverrides(() => sankofaEnv.hasPubspecYaml),
            getCurrentDirectory: () => tempDir,
          ),
          isTrue,
        );
      });
    });

    group('hasSankofaYaml', () {
      test('returns false when sankofa.yaml does not exist', () {
        final tempDir = Directory('temp');
        expect(
          IOOverrides.runZoned(
            () => runWithOverrides(() => sankofaEnv.hasSankofaYaml),
            getCurrentDirectory: () => tempDir,
          ),
          isFalse,
        );
      });

      test('returns true when sankofa.yaml does exist', () {
        final tempDir = Directory.systemTemp.createTempSync();
        File(
          p.join(tempDir.path, 'sankofa.yaml'),
        ).writeAsStringSync('app_id: test-app-id');
        expect(
          IOOverrides.runZoned(
            () => runWithOverrides(() => sankofaEnv.hasSankofaYaml),
            getCurrentDirectory: () => tempDir,
          ),
          isTrue,
        );
      });
    });

    group('pubspecContainsSankofaYaml', () {
      test('returns false when pubspec.yaml does not '
          'contain sankofa.yaml in assets', () {
        final tempDir = Directory.systemTemp.createTempSync();
        File(
          p.join(tempDir.path, 'pubspec.yaml'),
        ).writeAsStringSync('name: test');
        expect(
          IOOverrides.runZoned(
            () => runWithOverrides(
              () => sankofaEnv.pubspecContainsSankofaYaml,
            ),
            getCurrentDirectory: () => tempDir,
          ),
          isFalse,
        );
      });

      test('returns false when pubspec.yaml contains empty flutter config', () {
        final tempDir = Directory.systemTemp.createTempSync();
        File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: test
flutter:''');
        expect(
          IOOverrides.runZoned(
            () => runWithOverrides(
              () => sankofaEnv.pubspecContainsSankofaYaml,
            ),
            getCurrentDirectory: () => tempDir,
          ),
          isFalse,
        );
      });

      test('returns true when pubspec.yaml does '
          'contain sankofa.yaml in assets', () {
        final tempDir = Directory.systemTemp.createTempSync();
        File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: test
flutter:
  assets:
    - sankofa.yaml
''');
        expect(
          IOOverrides.runZoned(
            () => runWithOverrides(
              () => sankofaEnv.pubspecContainsSankofaYaml,
            ),
            getCurrentDirectory: () => tempDir,
          ),
          isTrue,
        );
      });
    });

    group('androidPackageName', () {
      test(
        'returns null when pubspec.yaml does not contain android module',
        () {
          final tempDir = Directory.systemTemp.createTempSync();
          File(
            p.join(tempDir.path, 'pubspec.yaml'),
          ).writeAsStringSync('name: test');
          expect(
            IOOverrides.runZoned(
              () => runWithOverrides(() => sankofaEnv.androidPackageName),
              getCurrentDirectory: () => tempDir,
            ),
            isNull,
          );
        },
      );

      test('returns correct package name when '
          'pubspec.yaml contains android module', () {
        final tempDir = Directory.systemTemp.createTempSync();
        File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: test
flutter:
  module:
    androidPackage: test-package
''');
        expect(
          IOOverrides.runZoned(
            () => runWithOverrides(() => sankofaEnv.androidPackageName),
            getCurrentDirectory: () => tempDir,
          ),
          equals('test-package'),
        );
      });
    });

    group('flutterRevision', () {
      test('returns correct revision', () {
        const revision = 'test-revision';
        File(p.join(sankofaRoot.path, 'bin', 'internal', 'flutter.version'))
          ..createSync(recursive: true)
          ..writeAsStringSync(revision, flush: true);
        expect(
          runWithOverrides(() => sankofaEnv.flutterRevision),
          equals(revision),
        );
      });

      test('trims revision file content', () {
        const revision = '''

test-revision

\r\n
''';
        File(p.join(sankofaRoot.path, 'bin', 'internal', 'flutter.version'))
          ..createSync(recursive: true)
          ..writeAsStringSync(revision, flush: true);

        expect(
          runWithOverrides(() => sankofaEnv.flutterRevision),
          'test-revision',
        );
      });

      test('uses override when provided', () {
        const revision = 'test-revision';
        const override = 'override-revision';
        File(p.join(sankofaRoot.path, 'bin', 'internal', 'flutter.version'))
          ..createSync(recursive: true)
          ..writeAsStringSync(revision, flush: true);
        expect(
          runWithOverrides(
            () => const SankofaEnv(
              flutterRevisionOverride: override,
            ).flutterRevision,
          ),
          equals(override),
        );
      });
    });

    group('usesSankofaCodePushPackage', () {
      group('when pubspec.yaml does not contain sankofa_code_push', () {
        setUp(() {
          final tempDir = Directory.systemTemp.createTempSync();
          File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: test

dependencies:
  clock: ^1.1.2
  collection: ^1.19.1
  crypto: ^3.0.6
  dart_frog: ^1.2.4
''');
          sankofaEnv = runWithOverrides(
            () => SankofaEnv(flutterProjectRootOverride: tempDir.path),
          );
        });

        test('returns false', () {
          expect(
            runWithOverrides(() => sankofaEnv.usesSankofaCodePushPackage),
            isFalse,
          );
        });
      });

      group('when pubspec.yaml contains sankofa_code_push', () {
        setUp(() {
          final tempDir = Directory.systemTemp.createTempSync();
          File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: test

dependencies:
  clock: ^1.1.2
  collection: ^1.19.1
  crypto: ^3.0.6
  dart_frog: ^1.2.4
  sankofa_code_push: ^1.0.0
''');
          sankofaEnv = runWithOverrides(
            () => SankofaEnv(flutterProjectRootOverride: tempDir.path),
          );
        });

        test('returns true', () {
          expect(
            runWithOverrides(() => sankofaEnv.usesSankofaCodePushPackage),
            isTrue,
          );
        });
      });
    });

    group('sankofaEngineRevision', () {
      test('returns correct revision', () {
        const engineRevision = 'test-revision';
        File(
            p.join(
              sankofaRoot.path,
              'bin',
              'cache',
              'flutter',
              flutterRevision,
              'bin',
              'internal',
              'engine.version',
            ),
          )
          ..createSync(recursive: true)
          ..writeAsStringSync(engineRevision, flush: true);
        expect(
          runWithOverrides(() => sankofaEnv.sankofaEngineRevision),
          equals(engineRevision),
        );
      });
    });

    group('hostedUrl', () {
      test('returns hosted url from env if available', () {
        when(
          () => platform.environment,
        ).thenReturn({'SANKOFA_HOSTED_URL': 'https://example.com'});
        expect(
          runWithOverrides(() => sankofaEnv.hostedUri),
          equals(Uri.parse('https://example.com')),
        );
      });

      test('falls back to sankofa.yaml', () {
        final directory = Directory.systemTemp.createTempSync();
        File(p.join(directory.path, 'sankofa.yaml')).writeAsStringSync('''
app_id: test-id
base_url: https://example.com''');
        expect(
          IOOverrides.runZoned(
            () => runWithOverrides(() => sankofaEnv.hostedUri),
            getCurrentDirectory: () => directory,
          ),
          equals(Uri.parse('https://example.com')),
        );
      });

      test('returns null when there is no env override or sankofa.yaml', () {
        expect(runWithOverrides(() => sankofaEnv.hostedUri), isNull);
      });

      test('returns null when unable to read sankofa.yaml', () {
        final directory = Directory.systemTemp.createTempSync();
        // This is not valid utf8 so readAsString will throw.
        File(
          p.join(directory.path, 'sankofa.yaml'),
        ).writeAsBytesSync([999999999999]);

        expect(
          IOOverrides.runZoned(
            () => runWithOverrides(() => sankofaEnv.hostedUri),
            getCurrentDirectory: () => directory,
          ),
          isNull,
        );
      });
    });

    group('canAcceptUserInput', () {
      late Stdin stdin;

      setUp(() {
        stdin = MockStdin();
      });

      group('when stdin has terminal', () {
        setUp(() {
          when(() => stdin.hasTerminal).thenReturn(true);
        });

        group('when not running on CI', () {
          setUp(() {
            when(() => platform.environment).thenReturn({});
          });

          test('returns true', () {
            expect(
              IOOverrides.runZoned(
                () => runWithOverrides(() => sankofaEnv.canAcceptUserInput),
                stdin: () => stdin,
              ),
              isTrue,
            );
          });
        });

        group('when running on CI', () {
          setUp(() {
            when(() => platform.environment).thenReturn({'CI': ''});
          });

          test('returns false', () {
            expect(
              IOOverrides.runZoned(
                () => runWithOverrides(() => sankofaEnv.canAcceptUserInput),
                stdin: () => stdin,
              ),
              isFalse,
            );
          });
        });
      });

      group('when stdin has terminal', () {
        setUp(() {
          when(() => stdin.hasTerminal).thenReturn(false);
        });

        test('returns true', () {
          expect(
            IOOverrides.runZoned(
              () => runWithOverrides(() => sankofaEnv.canAcceptUserInput),
              stdin: () => stdin,
            ),
            isFalse,
          );
        });
      });
    });

    group('authServiceUri', () {
      test('returns default URI when env var is not set', () {
        when(() => platform.environment).thenReturn({});
        expect(
          runWithOverrides(() => sankofaEnv.authServiceUri),
          equals(Uri.parse('https://auth.sankofa.dev')),
        );
      });

      test('returns URI from env var when set', () {
        when(() => platform.environment).thenReturn({
          'AUTH_SERVICE_URL': 'https://custom-auth.example.com',
        });
        expect(
          runWithOverrides(() => sankofaEnv.authServiceUri),
          equals(Uri.parse('https://custom-auth.example.com')),
        );
      });
    });

    group('jwtIssuer', () {
      test('returns default issuer when env var is not set', () {
        when(() => platform.environment).thenReturn({});
        expect(
          runWithOverrides(() => sankofaEnv.jwtIssuer),
          equals('https://auth.sankofa.dev'),
        );
      });

      test('returns issuer from env var when set', () {
        when(() => platform.environment).thenReturn({
          'SANKOFA_JWT_ISSUER': 'https://custom-issuer.example.com',
        });
        expect(
          runWithOverrides(() => sankofaEnv.jwtIssuer),
          equals('https://custom-issuer.example.com'),
        );
      });
    });

    group('isRunningOnCI', () {
      test('returns true if BOT variable is "true"', () {
        when(() => platform.environment).thenReturn({'BOT': 'true'});
        expect(runWithOverrides(() => sankofaEnv.isRunningOnCI), isTrue);
      });

      test('returns true if TRAVIS variable is "true"', () {
        when(() => platform.environment).thenReturn({'TRAVIS': 'true'});
        expect(runWithOverrides(() => sankofaEnv.isRunningOnCI), isTrue);
      });

      test('returns true if CONTINUOUS_INTEGRATION variable is "true"', () {
        when(
          () => platform.environment,
        ).thenReturn({'CONTINUOUS_INTEGRATION': 'true'});
        expect(runWithOverrides(() => sankofaEnv.isRunningOnCI), isTrue);
      });

      test('returns true if CI variable is set', () {
        when(() => platform.environment).thenReturn({'CI': ''});
        expect(runWithOverrides(() => sankofaEnv.isRunningOnCI), isTrue);
      });

      test('returns true if APPVEYOR variable is set', () {
        when(() => platform.environment).thenReturn({'APPVEYOR': ''});
        expect(runWithOverrides(() => sankofaEnv.isRunningOnCI), isTrue);
      });

      test('returns true if CIRRUS_CI variable is set', () {
        when(() => platform.environment).thenReturn({'CIRRUS_CI': ''});
        expect(runWithOverrides(() => sankofaEnv.isRunningOnCI), isTrue);
      });

      test(
        '''returns true if AWS_REGION and CODEBUILD_INITIATOR variables are set''',
        () {
          when(
            () => platform.environment,
          ).thenReturn({'AWS_REGION': '', 'CODEBUILD_INITIATOR': ''});
          expect(runWithOverrides(() => sankofaEnv.isRunningOnCI), isTrue);
        },
      );

      test('returns true if JENKINS_URL variable is set', () {
        when(() => platform.environment).thenReturn({'JENKINS_URL': ''});
        expect(runWithOverrides(() => sankofaEnv.isRunningOnCI), isTrue);
      });

      test('returns true if GITHUB_ACTIONS variable is set', () {
        when(() => platform.environment).thenReturn({'GITHUB_ACTIONS': ''});
        expect(runWithOverrides(() => sankofaEnv.isRunningOnCI), isTrue);
      });

      test('returns true if TF_BUILD is set', () {
        when(() => platform.environment).thenReturn({'TF_BUILD': 'True'});
        expect(runWithOverrides(() => sankofaEnv.isRunningOnCI), isTrue);
      });

      test('returns false if no relevant environment variables are set', () {
        when(() => platform.environment).thenReturn({});
        expect(runWithOverrides(() => sankofaEnv.isRunningOnCI), isFalse);
      });
    });
  });
}
