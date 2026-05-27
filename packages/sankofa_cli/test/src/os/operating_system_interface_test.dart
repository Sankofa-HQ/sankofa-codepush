import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:platform/platform.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:sankofa_cli/src/os/os.dart';
import 'package:sankofa_cli/src/platform.dart';
import 'package:sankofa_cli/src/sankofa_process.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(OperatingSystemInterface, () {
    late Platform platform;
    late SankofaProcess process;
    late SankofaProcessResult processResult;
    late OperatingSystemInterface osInterface;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {
          platformRef.overrideWith(() => platform),
          processRef.overrideWith(() => process),
        },
      );
    }

    setUp(() {
      platform = MockPlatform();
      process = MockSankofaProcess();
      processResult = MockProcessResult();

      when(() => platform.isLinux).thenReturn(false);
      when(() => platform.isMacOS).thenReturn(false);
      when(() => platform.isWindows).thenReturn(false);

      when(() => process.runSync(any(), any())).thenReturn(processResult);
      when(() => processResult.exitCode).thenReturn(ExitCode.success.code);
    });

    group('init', () {
      test(
        'throws UnsupportedError when operating system is not supported',
        () {
          expect(
            () => runWithOverrides(OperatingSystemInterface.new),
            throwsUnsupportedError,
          );
        },
      );
    });

    group('on macOS/Linux', () {
      setUp(() {
        when(() => platform.isMacOS).thenReturn(true);

        osInterface = runWithOverrides(OperatingSystemInterface.new);
      });

      group('which()', () {
        group('when no executable is found on PATH', () {
          setUp(() {
            when(() => processResult.exitCode).thenReturn(1);
          });

          test('returns null', () {
            expect(
              runWithOverrides(() => osInterface.which('sankofa')),
              isNull,
            );
          });
        });

        group('when executable is found on PATH', () {
          const sankofaPath = '/path/to/sankofa';
          setUp(() {
            when(() => processResult.stdout).thenReturn(sankofaPath);
          });

          test('returns path to executable', () {
            expect(
              runWithOverrides(() => osInterface.which('sankofa')),
              sankofaPath,
            );
          });
        });

        group('when executable contains leading and trailing newlines', () {
          const sankofaPath = '''


/path/to/sankofa

''';
          setUp(() {
            when(() => processResult.stdout).thenReturn(sankofaPath);
          });

          test('returns trimmed path to binary', () {
            expect(
              runWithOverrides(() => osInterface.which('sankofa')),
              equals('/path/to/sankofa'),
            );
          });
        });
      });
    });

    group('on Windows', () {
      setUp(() {
        when(() => platform.isWindows).thenReturn(true);
        osInterface = runWithOverrides(OperatingSystemInterface.new);
      });

      group('which()', () {
        group('when no executable is found on PATH', () {
          setUp(() {
            when(() => processResult.exitCode).thenReturn(1);
          });

          test('returns null', () {
            expect(
              runWithOverrides(() => osInterface.which('sankofa')),
              isNull,
            );
          });
        });

        group('when executable is found on PATH', () {
          const sankofaPath = r'C:\path\to\sankofa';
          setUp(() {
            when(() => processResult.stdout).thenReturn(sankofaPath);
          });

          test('returns path to executable', () {
            expect(
              runWithOverrides(() => osInterface.which('sankofa')),
              sankofaPath,
            );
          });
        });

        group('when multiple executables are found on PATH', () {
          const sankofaPath = r'C:\path\to\sankofa';
          const sankofaPaths = [
            r'C:\path\to\sankofa',
            r'C:\path\to\sankofa1',
            r'C:\path\to\sankofa2',
            r'C:\path\to\sankofa3',
          ];

          setUp(() {
            when(
              () => processResult.stdout,
            ).thenReturn(sankofaPaths.join('\r\n'));
          });

          test('returns first path to executable', () {
            expect(
              runWithOverrides(() => osInterface.which('sankofa')),
              sankofaPath,
            );
          });
        });
      });
    });
  });
}
