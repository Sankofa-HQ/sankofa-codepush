import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:sankofa_cli/src/executables/executables.dart';
import 'package:sankofa_cli/src/logging/logging.dart';
import 'package:sankofa_cli/src/sankofa_env.dart';
import 'package:sankofa_cli/src/sankofa_process.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group('SankofaTools', () {
    late File dartBinaryFile;
    late Directory flutterDirectory;
    late Directory tempDir;
    late SankofaLogger logger;
    late SankofaEnv sankofaEnv;
    late SankofaProcess process;
    late SankofaProcessResult processResult;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {
          processRef.overrideWith(() => process),
          sankofaEnvRef.overrideWith(() => sankofaEnv),
          loggerRef.overrideWith(() => logger),
          sankofaToolsRef,
        },
      );
    }

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync();
      flutterDirectory = Directory(p.join(tempDir.path, 'flutter'))
        ..createSync();
      dartBinaryFile = File(p.join(tempDir.path, 'dart'))..createSync();
      processResult = MockProcessResult();
      sankofaEnv = MockSankofaEnv();
      process = MockSankofaProcess();
      logger = MockSankofaLogger();

      when(() => processResult.exitCode).thenReturn(0);
      when(() => processResult.stdout).thenReturn('');
      when(() => processResult.stderr).thenReturn('');

      when(() => sankofaEnv.flutterDirectory).thenReturn(flutterDirectory);
      when(() => sankofaEnv.dartBinaryFile).thenReturn(dartBinaryFile);

      when(
        () => process.run(
          any(),
          any(),
          workingDirectory: any(named: 'workingDirectory'),
        ),
      ).thenAnswer((_) async => processResult);
    });

    test('have access a reference to sankofa tool', () {
      expect(
        runScoped(() => sankofaTools, values: {sankofaToolsRef}),
        isA<SankofaTools>(),
      );
    });

    test('makes the correct cli call', () async {
      await runWithOverrides(
        () => sankofaTools.package(
          patchPath: 'patchPath',
          outputPath: 'outputPath',
        ),
      );

      verify(
        () => process.run(
          dartBinaryFile.path,
          any(
            that: containsAllInOrder([
              'run',
              'sankofa_tools',
              'package',
              '-p',
              'patchPath',
              '-o',
              'outputPath',
            ]),
          ),
          workingDirectory: p.join(
            flutterDirectory.path,
            'packages',
            'sankofa_tools',
          ),
        ),
      ).called(1);
    });

    group('when the command fails', () {
      setUp(() {
        when(() => processResult.exitCode).thenReturn(1);
        when(() => processResult.stdout).thenReturn('stdout');
        when(() => processResult.stderr).thenReturn('stderr');
      });

      test('throws a PackageFailedException', () {
        expect(
          () => runWithOverrides(
            () => sankofaTools.package(
              patchPath: 'patchPath',
              outputPath: 'outputPath',
            ),
          ),
          throwsA(
            isA<PackageFailedException>().having(
              (e) => e.toString(),
              'message',
              '''
Failed to create package (exit code ${processResult.exitCode}).
  stdout: ${processResult.stdout}
  stderr: ${processResult.stderr}''',
            ),
          ),
        );
      });
    });

    group('when the sankofa tools directory exists', () {
      test('isSupported returns true', () {
        Directory(
          p.join(flutterDirectory.path, 'packages', 'sankofa_tools'),
        ).createSync(recursive: true);
        final isSupported = runWithOverrides(
          () => sankofaTools.isSupported(),
        );
        expect(isSupported, isTrue);
      });
    });

    group('when the sankofa tools directory does not exist', () {
      test('isSupported returns false', () {
        final isSupported = runWithOverrides(
          () => sankofaTools.isSupported(),
        );
        expect(isSupported, isFalse);
      });
    });
  });
}
