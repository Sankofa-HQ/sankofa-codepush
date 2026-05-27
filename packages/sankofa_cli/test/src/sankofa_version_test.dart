import 'dart:io';

import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:sankofa_cli/src/executables/executables.dart';
import 'package:sankofa_cli/src/sankofa_version.dart';
import 'package:test/test.dart';

import 'mocks.dart';

void main() {
  group(SankofaVersion, () {
    const currentSankofaRevision = 'revision-1';
    const newerSankofaRevision = 'revision-2';

    late Git git;
    late SankofaVersion sankofaVersionManager;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(body, values: {gitRef.overrideWith(() => git)});
    }

    setUpAll(() {
      registerFallbackValue(Directory(''));
    });

    setUp(() {
      git = MockGit();
      sankofaVersionManager = SankofaVersion();

      when(
        () => git.fetch(
          directory: any(named: 'directory'),
          args: any(named: 'args'),
        ),
      ).thenAnswer((_) async => {});
      when(
        () => git.remote(
          directory: any(named: 'directory'),
          args: any(named: 'args'),
        ),
      ).thenAnswer((_) async => {});
      when(
        () => git.revParse(
          revision: any(named: 'revision'),
          directory: any(named: 'directory'),
        ),
      ).thenAnswer((_) async => currentSankofaRevision);
      when(
        () => git.reset(
          revision: any(named: 'revision'),
          directory: any(named: 'directory'),
          args: any(named: 'args'),
        ),
      ).thenAnswer((_) async {});
    });

    group('isSankofaVersionCurrent', () {
      test('returns true if current and latest git hashes match', () async {
        expect(
          await runWithOverrides(sankofaVersionManager.isLatest),
          isTrue,
        );
        verify(
          () => git.fetch(
            directory: any(named: 'directory'),
            args: ['--tags'],
          ),
        ).called(1);
        verify(
          () => git.revParse(
            revision: 'HEAD',
            directory: any(named: 'directory'),
          ),
        ).called(1);
        verify(
          () => git.revParse(
            revision: '@{upstream}',
            directory: any(named: 'directory'),
          ),
        ).called(1);
      });

      test('returns false if current and latest git hashes differ', () async {
        when(
          () => git.revParse(
            revision: any(named: 'revision'),
            directory: any(named: 'directory'),
          ),
        ).thenAnswer((invocation) async {
          final revision = invocation.namedArguments[#revision] as String;
          if (revision == 'HEAD') {
            return currentSankofaRevision;
          } else if (revision == '@{upstream}') {
            return newerSankofaRevision;
          }
          throw UnsupportedError('Unexpected revision: $revision');
        });

        expect(
          await runWithOverrides(sankofaVersionManager.isLatest),
          isFalse,
        );
        verify(
          () => git.fetch(
            directory: any(named: 'directory'),
            args: ['--tags'],
          ),
        ).called(1);
        verify(
          () => git.revParse(
            revision: 'HEAD',
            directory: any(named: 'directory'),
          ),
        ).called(1);
        verify(
          () => git.revParse(
            revision: '@{upstream}',
            directory: any(named: 'directory'),
          ),
        ).called(1);
      });

      test(
        'throws ProcessException if git command exits with code other than 0',
        () async {
          const errorMessage = 'oh no!';
          when(
            () => git.revParse(
              revision: any(named: 'revision'),
              directory: any(named: 'directory'),
            ),
          ).thenThrow(
            ProcessException(
              'git',
              ['rev-parse', 'HEAD'],
              errorMessage,
              ExitCode.software.code,
            ),
          );

          expect(
            runWithOverrides(sankofaVersionManager.isLatest),
            throwsA(
              isA<ProcessException>().having(
                (e) => e.message,
                'message',
                errorMessage,
              ),
            ),
          );
        },
      );
    });

    group('attemptReset', () {
      test('completes when git command exits with code 0', () async {
        expect(
          runWithOverrides(
            () => sankofaVersionManager.attemptReset(revision: 'HEAD'),
          ),
          completes,
        );
      });

      test(
        'throws ProcessException when git command exits with non-zero code',
        () async {
          const errorMessage = 'oh no!';
          when(
            () => git.reset(
              revision: any(named: 'revision'),
              directory: any(named: 'directory'),
              args: any(named: 'args'),
            ),
          ).thenThrow(
            ProcessException(
              'git',
              ['reset', '--hard', 'HEAD'],
              errorMessage,
              ExitCode.software.code,
            ),
          );

          expect(
            runWithOverrides(
              () => sankofaVersionManager.attemptReset(revision: 'HEAD'),
            ),
            throwsA(
              isA<ProcessException>().having(
                (e) => e.message,
                'message',
                errorMessage,
              ),
            ),
          );
        },
      );
    });

    group('isTrackingStable', () {
      group('when on the stable branch', () {
        setUp(() {
          when(
            () => git.currentBranch(directory: any(named: 'directory')),
          ).thenAnswer((_) async => 'stable');
        });

        test('returns true', () async {
          expect(
            await runWithOverrides(sankofaVersionManager.isTrackingStable),
            isTrue,
          );
        });
      });

      group('when on a branch other than stable', () {
        setUp(() {
          when(
            () => git.currentBranch(directory: any(named: 'directory')),
          ).thenAnswer((_) async => 'main');
        });

        test('returns false', () async {
          expect(
            await runWithOverrides(sankofaVersionManager.isTrackingStable),
            isFalse,
          );
        });
      });
    });
  });
}
