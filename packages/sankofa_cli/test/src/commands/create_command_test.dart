import 'package:args/args.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:sankofa_cli/src/commands/commands.dart';
import 'package:sankofa_cli/src/sankofa_cli_command_runner.dart';
import 'package:sankofa_cli/src/sankofa_env.dart';
import 'package:sankofa_cli/src/sankofa_process.dart';
import 'package:sankofa_cli/src/sankofa_validator.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(CreateCommand, () {
    const args = ['my_app'];
    late SankofaProcess process;
    late ArgResults argResults;
    late SankofaCliCommandRunner runner;
    late SankofaValidator sankofaValidator;
    late CreateCommand command;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          processRef.overrideWith(() => process),
          sankofaValidatorRef.overrideWith(() => sankofaValidator),
        },
      );
    }

    setUp(() {
      argResults = MockArgResults();
      process = MockSankofaProcess();
      runner = MockSankofaCliCommandRunner();
      sankofaValidator = MockSankofaValidator();
      command = runWithOverrides(CreateCommand.new)
        ..testArgResults = argResults
        ..testRunner = runner;

      when(() => argResults.rest).thenReturn(args);

      when(
        () => runner.run(any()),
      ).thenAnswer((_) async => ExitCode.success.code);

      when(
        () => process.stream('flutter', ['create', ...args]),
      ).thenAnswer((_) async => ExitCode.success.code);

      when(
        () => sankofaValidator.validatePreconditions(
          checkUserIsAuthenticated: true,
        ),
      ).thenAnswer((_) async {});
    });

    test('has correct name and description', () {
      expect(command.name, equals('create'));
      expect(
        command.description,
        equals('Create a new Flutter project with Sankofa.'),
      );
    });

    test('runs the `flutter create` command', () async {
      await expectLater(
        runWithOverrides(command.run),
        completion(equals(ExitCode.success.code)),
      );

      verify(() => process.stream('flutter', ['create', ...args])).called(1);
    });

    group('when validation fails', () {
      setUp(() {
        when(
          () => sankofaValidator.validatePreconditions(
            checkUserIsAuthenticated: true,
          ),
        ).thenThrow(ValidationFailedException());
      });

      test('exits with code 70', () async {
        await expectLater(
          runWithOverrides(command.run),
          completion(equals(ExitCode.config.code)),
        );

        verify(
          () => sankofaValidator.validatePreconditions(
            checkUserIsAuthenticated: true,
          ),
        ).called(1);
      });
    });

    test('runs the sankofa init command', () async {
      when(() => runner.run(any())).thenAnswer((invocation) async {
        final runnerArgs = invocation.positionalArguments.first as List;
        if (runnerArgs.first == 'init') {
          expect(
            p.basename(sankofaEnv.getFlutterProjectRoot()!.path),
            args.first,
          );
        }
        return ExitCode.success.code;
      });
      await expectLater(
        runWithOverrides(command.run),
        completion(equals(ExitCode.success.code)),
      );

      verify(() => runner.run(['init'])).called(1);
    });

    group('when passing --help', () {
      setUp(() {
        when(() => argResults.rest).thenReturn(['--help']);
        when(
          () => process.stream('flutter', ['create', '--help']),
        ).thenAnswer((_) async => ExitCode.success.code);
      });

      test('only runs flutter create', () async {
        await expectLater(
          runWithOverrides(command.run),
          completion(equals(ExitCode.success.code)),
        );

        verify(() => process.stream('flutter', ['create', '--help'])).called(1);
        verifyNever(() => runner.run(any()));
      });
    });

    group('when flutter create fails', () {
      setUp(() {
        when(
          () => process.stream('flutter', ['create', ...args]),
        ).thenAnswer((_) async => 1);
      });

      test('exits', () async {
        await expectLater(
          runWithOverrides(command.run),
          completion(equals(1)),
        );

        verify(() => process.stream('flutter', ['create', ...args])).called(1);
        verifyNever(() => runner.run(any()));
      });
    });
  });
}
