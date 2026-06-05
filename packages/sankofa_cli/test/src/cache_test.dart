import 'dart:async';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:http/http.dart' as http;
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:sankofa_cli/src/abi.dart';
import 'package:sankofa_cli/src/artifact_manager.dart';
import 'package:sankofa_cli/src/cache.dart';
import 'package:sankofa_cli/src/checksum_checker.dart';
import 'package:sankofa_cli/src/flutter_version_constraints.dart';
import 'package:sankofa_cli/src/http_client/http_client.dart';
import 'package:sankofa_cli/src/logging/logging.dart';
import 'package:sankofa_cli/src/platform.dart';
import 'package:sankofa_cli/src/sankofa_env.dart';
import 'package:sankofa_cli/src/sankofa_flutter.dart';
import 'package:sankofa_cli/src/sankofa_process.dart';
import 'package:test/test.dart';

import 'fakes.dart';
import 'mocks.dart';

void main() {
  group(Cache, () {
    const sankofaEngineRevision = 'test-revision';

    late LocalAbi mockAbi;
    late ArtifactManager artifactManager;
    late Cache cache;
    late ChecksumChecker checksumChecker;
    late Directory sankofaRoot;
    late http.Client httpClient;
    late SankofaLogger logger;
    late Platform platform;
    late Process chmodProcess;
    late Progress progress;
    late SankofaEnv sankofaEnv;
    late SankofaFlutter sankofaFlutter;
    late SankofaProcess sankofaProcess;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {
          abiRef.overrideWith(() => mockAbi),
          artifactManagerRef.overrideWith(() => artifactManager),
          cacheRef.overrideWith(() => cache),
          checksumCheckerRef.overrideWith(() => checksumChecker),
          httpClientRef.overrideWith(() => httpClient),
          loggerRef.overrideWith(() => logger),
          platformRef.overrideWith(() => platform),
          processRef.overrideWith(() => sankofaProcess),
          sankofaEnvRef.overrideWith(() => sankofaEnv),
          sankofaFlutterRef.overrideWith(() => sankofaFlutter),
        },
      );
    }

    void setMockPlatform(String name) {
      assert(
        Platform.operatingSystemValues.contains(name),
        'Unrecognized platform name',
      );
      when(() => platform.isMacOS).thenReturn(name == 'macos');
      when(() => platform.isWindows).thenReturn(name == 'windows');
      when(() => platform.isLinux).thenReturn(name == 'linux');
      when(() => platform.isAndroid).thenReturn(name == 'android');
      when(() => platform.isFuchsia).thenReturn(name == 'fuchsia');
      when(() => platform.isIOS).thenReturn(name == 'ios');
    }

    setUpAll(() {
      registerFallbackValue(Directory(''));
      registerFallbackValue(File(''));
      registerFallbackValue(FakeBaseRequest());
    });

    setUp(() {
      mockAbi = MockAbi();
      artifactManager = MockArtifactManager();
      chmodProcess = MockProcess();
      checksumChecker = MockChecksumChecker();
      httpClient = MockHttpClient();
      logger = MockSankofaLogger();
      platform = MockPlatform();
      progress = MockProgress();
      sankofaEnv = MockSankofaEnv();
      sankofaFlutter = MockSankofaFlutter();
      sankofaProcess = MockSankofaProcess();

      when(() => mockAbi.current).thenReturn(Abi.macosX64);
      when(
        () => sankofaFlutter.resolveFlutterVersion(any()),
      ).thenAnswer((_) async => null);

      sankofaRoot = Directory.systemTemp.createTempSync();
      // Match the on-disk layout AotToolsArtifact expects so isValid()
      // short-circuits and no download/pub-get runs in these tests.
      File(
        p.join(sankofaRoot.path, 'third_party', 'aot_tools', 'bin',
            'aot_tools.dart'),
      ).createSync(recursive: true);
      File(
        p.join(sankofaRoot.path, 'third_party', 'aot_tools', '.dart_tool',
            'package_config.json'),
      )
        ..createSync(recursive: true)
        ..writeAsStringSync('{}');
      when(
        () => artifactManager.extractZip(
          zipFile: any(named: 'zipFile'),
          outputDirectory: any(named: 'outputDirectory'),
        ),
      ).thenAnswer((invocation) async {
        (invocation.namedArguments[#outputDirectory] as Directory).createSync(
          recursive: true,
        );
      });
      when(() => logger.progress(any())).thenReturn(progress);
      when(
        () => sankofaEnv.sankofaEngineRevision,
      ).thenReturn(sankofaEngineRevision);
      when(
        () => sankofaEnv.flutterRevision,
      ).thenReturn('test-flutter-revision');
      when(() => sankofaEnv.sankofaRoot).thenReturn(sankofaRoot);

      when(() => platform.environment).thenReturn({});
      setMockPlatform(Platform.macOS);
      when(
        () => sankofaProcess.start(any(), any()),
      ).thenAnswer((_) async => chmodProcess);
      when(
        () => chmodProcess.exitCode,
      ).thenAnswer((_) async => ExitCode.success.code);
      when(() => httpClient.send(any())).thenAnswer(
        (_) async => http.StreamedResponse(
          Stream.value(ZipEncoder().encode(Archive())),
          HttpStatus.ok,
        ),
      );
      when(() => checksumChecker.checkFile(any(), any())).thenReturn(true);

      cache = runWithOverrides(Cache.new);
    });

    test('can be instantiated w/out args', () {
      expect(Cache.new, returnsNormally);
    });

    group(CacheUpdateFailure, () {
      test('overrides toString', () {
        const exception = CacheUpdateFailure('test');
        expect(exception.toString(), equals('CacheUpdateFailure: test'));
      });
    });

    group('getArtifactDirectory', () {
      test('returns correct directory', () {
        final directory = runWithOverrides(
          () => cache.getArtifactDirectory('test'),
        );
        expect(
          directory.path.endsWith(p.join('bin', 'cache', 'artifacts', 'test')),
          isTrue,
        );
      });
    });

    group('getPreviewDirectory', () {
      test('returns correct directory', () {
        final directory = runWithOverrides(
          () => cache.getPreviewDirectory('test'),
        );
        expect(
          directory.path.endsWith(p.join('bin', 'cache', 'previews', 'test')),
          isTrue,
        );
      });
    });

    group('clear', () {
      test('deletes the cache directory', () async {
        final sankofaCacheDirectory = runWithOverrides(
          () => Cache.sankofaCacheDirectory,
        )..createSync(recursive: true);
        expect(sankofaCacheDirectory.existsSync(), isTrue);
        await runWithOverrides(cache.clear);
        expect(sankofaCacheDirectory.existsSync(), isFalse);
      });

      test('does nothing if directory does not exist', () {
        final sankofaCacheDirectory = runWithOverrides(
          () => Cache.sankofaCacheDirectory,
        );
        expect(sankofaCacheDirectory.existsSync(), isFalse);
        unawaited(runWithOverrides(cache.clear));
        expect(sankofaCacheDirectory.existsSync(), isFalse);
      });
    });

    group('updateAll', () {
      group('patch', () {
        group('fileName', () {
          group('when on Windows', () {
            setUp(() {
              setMockPlatform(Platform.windows);
            });

            test('has exe extension', () {
              final fileName = runWithOverrides(
                () => PatchArtifact(cache: cache, platform: platform).fileName,
              );
              expect(fileName, equals('patch.exe'));
            });
          });

          group('when not on Windows', () {
            setUp(() {
              setMockPlatform(Platform.linux);
            });

            test('does not have exe extension', () {
              final fileName = runWithOverrides(
                () => PatchArtifact(cache: cache, platform: platform).fileName,
              );
              expect(fileName, equals('patch'));
            });
          });
        });

        group('storageUrl', () {
          group('when on macOS', () {
            setUp(() {
              setMockPlatform(Platform.macOS);
            });

            test(
              'uses darwin-arm64 on Apple Silicon when the Flutter version '
              'satisfies the arm64 patch constraint',
              () async {
                when(() => mockAbi.current).thenReturn(Abi.macosArm64);
                when(
                  () => sankofaFlutter.resolveFlutterVersion(any()),
                ).thenAnswer(
                  (_) async => arm64PatchSupportConstraint.minVersion,
                );
                final url = await runWithOverrides(
                  () => PatchArtifact(
                    cache: cache,
                    platform: platform,
                  ).storageUrl,
                );
                expect(url, contains('patch-darwin-arm64.zip'));
              },
            );

            test(
              'uses darwin-x64 on Apple Silicon when the Flutter version '
              'is below the arm64 patch constraint floor',
              () async {
                when(() => mockAbi.current).thenReturn(Abi.macosArm64);
                when(
                  () => sankofaFlutter.resolveFlutterVersion(any()),
                ).thenAnswer((_) async => Version(3, 41, 6));
                final url = await runWithOverrides(
                  () => PatchArtifact(
                    cache: cache,
                    platform: platform,
                  ).storageUrl,
                );
                expect(url, contains('patch-darwin-x64.zip'));
              },
            );

            test('uses darwin-x64 on Intel', () async {
              when(() => mockAbi.current).thenReturn(Abi.macosX64);
              final url = await runWithOverrides(
                () =>
                    PatchArtifact(cache: cache, platform: platform).storageUrl,
              );
              expect(url, contains('patch-darwin-x64.zip'));
            });
          });

          group('when on Linux', () {
            setUp(() {
              setMockPlatform(Platform.linux);
            });

            test('uses linux-x64', () async {
              final url = await runWithOverrides(
                () =>
                    PatchArtifact(cache: cache, platform: platform).storageUrl,
              );
              expect(url, contains('patch-linux-x64.zip'));
            });
          });

          group('when on Windows', () {
            setUp(() {
              setMockPlatform(Platform.windows);
            });

            test('uses windows-x64', () async {
              final url = await runWithOverrides(
                () =>
                    PatchArtifact(cache: cache, platform: platform).storageUrl,
              );
              expect(url, contains('patch-windows-x64.zip'));
            });
          });
        });

        group('when an exception happens', () {
          test('throws CacheUpdateFailure', () async {
            const exception = SocketException('test');
            when(() => httpClient.send(any())).thenThrow(exception);
            await expectLater(
              runWithOverrides(() => cache.updateAll(Duration.zero)),
              throwsA(
                isA<CacheUpdateFailure>().having(
                  (e) => e.message,
                  'message',
                  contains('Failed to download patch: $exception'),
                ),
              ),
            );
          });

          test('retries and log', () async {
            const exception = SocketException('test');
            when(() => httpClient.send(any())).thenThrow(exception);

            await expectLater(
              runWithOverrides(() => cache.updateAll(Duration.zero)),
              throwsA(isA<CacheUpdateFailure>()),
            );

            verify(
              () => logger.detail('Failed to update patch, retrying...'),
            ).called(2);
          });
        });

        test('throws CacheUpdateFailure if a non-200 is returned', () async {
          when(() => httpClient.send(any())).thenAnswer(
            (_) async => http.StreamedResponse(
              const Stream.empty(),
              HttpStatus.notFound,
              reasonPhrase: 'Not Found',
            ),
          );
          await expectLater(
            runWithOverrides(() => cache.updateAll(Duration.zero)),
            throwsA(
              isA<CacheUpdateFailure>().having(
                (e) => e.message,
                'message',
                contains('Failed to download patch: 404 Not Found'),
              ),
            ),
          );
        });

        test('aot_tools is bundled — never hits httpClient', () async {
          await expectLater(
            runWithOverrides(() => cache.updateAll(Duration.zero)),
            completes,
          );
          final requests = verify(
            () => httpClient.send(captureAny()),
          ).captured.cast<http.BaseRequest>().map((r) => r.url.path).toList();
          expect(
            requests.any((p) => p.contains('aot-tools') || p.contains('aot_tools')),
            isFalse,
          );
        });

        test('downloads correct artifacts', () async {
          final patchArtifactDirectory = runWithOverrides(
            () => cache.getArtifactDirectory('patch'),
          );
          expect(patchArtifactDirectory.existsSync(), isFalse);
          await expectLater(
            runWithOverrides(() => cache.updateAll(Duration.zero)),
            completes,
          );
          expect(patchArtifactDirectory.existsSync(), isTrue);
        });

        group('when extraction fails', () {
          setUp(() {
            when(
              () => artifactManager.extractZip(
                zipFile: any(named: 'zipFile'),
                outputDirectory: any(named: 'outputDirectory'),
              ),
            ).thenThrow(Exception('test'));
          });

          test('throws exception, logs failure', () async {
            await expectLater(
              () => runWithOverrides(() => cache.updateAll(Duration.zero)),
              throwsException,
            );
            verify(() => progress.fail()).called(3);
          });
        });

        group('when checksum validation fails', () {
          setUp(() {
            when(
              () => checksumChecker.checkFile(any(), any()),
            ).thenReturn(false);
          });

          test('fails with the correct message', () async {
            await expectLater(
              () => runWithOverrides(() => cache.updateAll(Duration.zero)),
              throwsA(
                isA<CacheUpdateFailure>().having(
                  (e) => e.message,
                  'message',
                  contains(
                    'Failed to download bundletool.jar: checksum mismatch',
                  ),
                ),
              ),
            );

            verify(() => progress.fail()).called(3);
          });
        });

        test('pulls correct artifact for MacOS', () async {
          setMockPlatform(Platform.macOS);

          await expectLater(
            runWithOverrides(() => cache.updateAll(Duration.zero)),
            completes,
          );

          final requests = verify(
            () => httpClient.send(captureAny()),
          ).captured.cast<http.BaseRequest>().map((r) => r.url).toList();

          String perEngine(String name) {
            final bucket = cache.storageBucket;
            final prefix = bucket.isEmpty
                ? cache.storageBaseUrl
                : '${cache.storageBaseUrl}/$bucket';
            return '$prefix/sankofa/$sankofaEngineRevision/$name';
          }

          final expected = [
            perEngine('patch-darwin-x64.zip'),
            'https://github.com/google/bundletool/releases/download/1.18.1/bundletool-all-1.18.1.jar',
          ].map(Uri.parse).toList();

          expect(requests, equals(expected));
        });

        test('pulls correct artifact for Windows', () async {
          setMockPlatform(Platform.windows);

          await expectLater(
            runWithOverrides(() => cache.updateAll(Duration.zero)),
            completes,
          );

          final requests = verify(
            () => httpClient.send(captureAny()),
          ).captured.cast<http.BaseRequest>().map((r) => r.url).toList();

          String perEngine(String name) {
            final bucket = cache.storageBucket;
            final prefix = bucket.isEmpty
                ? cache.storageBaseUrl
                : '${cache.storageBaseUrl}/$bucket';
            return '$prefix/sankofa/$sankofaEngineRevision/$name';
          }

          final expected = [
            perEngine('patch-windows-x64.zip'),
            'https://github.com/google/bundletool/releases/download/1.18.1/bundletool-all-1.18.1.jar',
          ].map(Uri.parse).toList();

          expect(requests, equals(expected));
        });

        test('pulls correct artifact for Linux', () async {
          setMockPlatform(Platform.linux);

          await expectLater(
            runWithOverrides(() => cache.updateAll(Duration.zero)),
            completes,
          );

          final requests = verify(
            () => httpClient.send(captureAny()),
          ).captured.cast<http.BaseRequest>().map((r) => r.url).toList();

          String perEngine(String name) {
            final bucket = cache.storageBucket;
            final prefix = bucket.isEmpty
                ? cache.storageBaseUrl
                : '${cache.storageBaseUrl}/$bucket';
            return '$prefix/sankofa/$sankofaEngineRevision/$name';
          }

          final expected = [
            perEngine('patch-linux-x64.zip'),
            'https://github.com/google/bundletool/releases/download/1.18.1/bundletool-all-1.18.1.jar',
          ].map(Uri.parse).toList();

          expect(requests, equals(expected));
        });
      });
    });
  });

  group(CachedArtifact, () {
    late Cache cache;
    late ChecksumChecker checksumChecker;
    late http.Client httpClient;
    late SankofaLogger logger;
    late Platform platform;
    late Progress progress;
    late _TestCachedArtifact cachedArtifact;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {
          checksumCheckerRef.overrideWith(() => checksumChecker),
          httpClientRef.overrideWith(() => httpClient),
          loggerRef.overrideWith(() => logger),
        },
      );
    }

    setUpAll(() {
      registerFallbackValue(FakeBaseRequest());
      registerFallbackValue(File(''));
    });

    setUp(() {
      cache = MockCache();
      checksumChecker = MockChecksumChecker();
      httpClient = MockHttpClient();
      logger = MockSankofaLogger();
      platform = MockPlatform();
      progress = MockProgress();

      when(() => httpClient.send(any())).thenAnswer(
        (_) async =>
            http.StreamedResponse(const Stream.empty(), HttpStatus.notFound),
      );

      when(() => logger.progress(any())).thenReturn(progress);

      cachedArtifact = _TestCachedArtifact(cache: cache, platform: platform);
    });

    group('isValid', () {
      group('when the artifact file does not exist', () {
        test('returns false', () async {
          expect(await runWithOverrides(cachedArtifact.isValid), isFalse);
        });
      });

      group('when the artifact file exists', () {
        setUp(() {
          cachedArtifact.file.createSync(recursive: true);
        });

        group('when the stamp file does not exist', () {
          test('returns false', () async {
            expect(await runWithOverrides(cachedArtifact.isValid), isFalse);
          });
        });

        group('when the stamp file exists', () {
          setUp(() {
            cachedArtifact.stampFile.createSync();
          });

          group('when there is no expected checksum', () {
            setUp(() {
              cachedArtifact.checksumOverride = null;
            });

            test('returns true', () async {
              expect(await runWithOverrides(cachedArtifact.isValid), isTrue);
            });
          });

          group('when there is an expected checksum', () {
            setUp(() {
              cachedArtifact.checksumOverride = 'some-checksum';
            });

            group('when the checksum matches', () {
              setUp(() {
                when(
                  () => checksumChecker.checkFile(any(), any()),
                ).thenReturn(true);
              });

              test('returns true', () async {
                expect(await runWithOverrides(cachedArtifact.isValid), isTrue);
              });
            });

            group('when the checksum does not match', () {
              setUp(() {
                when(
                  () => checksumChecker.checkFile(any(), any()),
                ).thenReturn(false);
              });

              test('returns false', () async {
                expect(await runWithOverrides(cachedArtifact.isValid), isFalse);
              });
            });
          });
        });
      });
    });

    group('update', () {
      group('when artifact exists on disk', () {
        setUp(() {
          cachedArtifact.file.createSync(recursive: true);
          cachedArtifact.stampFile.createSync(recursive: true);
        });

        test(
          'deletes existing artifact and stamp file before updating',
          () async {
            expect(cachedArtifact.file.existsSync(), isTrue);
            expect(cachedArtifact.stampFile.existsSync(), isTrue);

            // This will fail due to the mock http client returning a 404.
            await expectLater(
              () => runWithOverrides(cachedArtifact.update),
              throwsException,
            );

            expect(cachedArtifact.file.existsSync(), isFalse);
            expect(cachedArtifact.stampFile.existsSync(), isFalse);
          },
        );
      });
    });
  });
}

class _TestCachedArtifact extends CachedArtifact {
  _TestCachedArtifact({required super.cache, required super.platform});

  String? checksumOverride;

  @override
  String? get checksum => checksumOverride;

  final Directory _location = Directory.systemTemp.createTempSync();

  @override
  bool get isExecutable => throw UnimplementedError();

  @override
  String get fileName => 'test_artifact.exe';

  @override
  File get file => File(p.join(_location.path, fileName));

  @override
  Future<String> get storageUrl async =>
      'https://example.com/test_artifact.exe';
}
