import 'package:mason_logger/mason_logger.dart';
import 'package:mocktail/mocktail.dart';
import 'package:platform/platform.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:sankofa_cli/src/auth/auth.dart';
import 'package:sankofa_cli/src/config/config.dart';
import 'package:sankofa_cli/src/logging/logging.dart';
import 'package:sankofa_cli/src/platform.dart';
import 'package:sankofa_cli/src/sankofa_env.dart';
import 'package:sankofa_cli/src/sankofa_validator.dart';
import 'package:sankofa_cli/src/validators/validators.dart';
import 'package:sankofa_code_push_protocol/sankofa_code_push_protocol.dart';
import 'package:test/test.dart';

import 'mocks.dart';

void main() {
  group(SankofaValidator, () {
    late Auth auth;
    late SankofaLogger logger;
    late Platform platform;
    late Validator validator;
    late SankofaEnv sankofaEnv;
    late SankofaValidator sankofaValidator;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {
          authRef.overrideWith(() => auth),
          loggerRef.overrideWith(() => logger),
          platformRef.overrideWith(() => platform),
          sankofaEnvRef.overrideWith(() => sankofaEnv),
        },
      );
    }

    setUp(() {
      auth = MockAuth();
      logger = MockSankofaLogger();
      platform = MockPlatform();
      sankofaEnv = MockSankofaEnv();
      validator = MockValidator();
      sankofaValidator = runWithOverrides(SankofaValidator.new);
    });

    group('PreconditionFailedException', () {
      test('have correct exit codes', () {
        expect(SankofaNotInitializedException().exitCode, ExitCode.config);
        expect(UserNotAuthorizedException().exitCode, ExitCode.noUser);
        expect(ValidationFailedException().exitCode, ExitCode.config);
        expect(
          UnsupportedOperatingSystemException().exitCode,
          ExitCode.unavailable,
        );
      });
    });

    group('validatePreconditions', () {
      test('throws UnsupportedOperatingSystemException '
          'when the operating system is not supported', () async {
        when(() => platform.operatingSystem).thenReturn(Platform.linux);
        const supportedOperatingSystems = {Platform.macOS, Platform.windows};
        await expectLater(
          runWithOverrides(
            () => sankofaValidator.validatePreconditions(
              supportedOperatingSystems: supportedOperatingSystems,
            ),
          ),
          throwsA(isA<UnsupportedOperatingSystemException>()),
        );
        verify(
          () => logger.err(
            '''This command is only supported on ${supportedOperatingSystems.join(' ,')}.''',
          ),
        ).called(1);
      });

      test('throws UserNotAuthorizedException '
          'when user is not authenticated', () async {
        when(() => auth.isAuthenticated).thenReturn(false);
        await expectLater(
          runWithOverrides(
            () => sankofaValidator.validatePreconditions(
              checkUserIsAuthenticated: true,
            ),
          ),
          throwsA(isA<UserNotAuthorizedException>()),
        );
        verifyInOrder([
          () => logger.err('You must be logged in to run this command.'),
          () => logger.info(
            '''If you already have an account, run ${lightCyan.wrap('sankofa login')} to sign in.''',
          ),
          () => logger.info(
            '''If you don't have a Sankofa account, go to ${link(uri: Uri.parse('https://console.sankofa.dev'))} to create one.''',
          ),
        ]);
      });

      group(
        '''when sankofa has not been properly initialized for the current app''',
        () {
          group("when sankofa.yaml doesn't exist", () {
            setUp(() {
              when(() => sankofaEnv.hasSankofaYaml).thenReturn(false);
            });

            test(
              '''prints error message and throws SankofaNotInitializedException''',
              () async {
                await expectLater(
                  runWithOverrides(
                    () => sankofaValidator.validatePreconditions(
                      checkSankofaInitialized: true,
                    ),
                  ),
                  throwsA(isA<SankofaNotInitializedException>()),
                );
                verifyInOrder([
                  () => logger.err(
                    '''Unable to find sankofa.yaml. Are you in a sankofa app directory?''',
                  ),
                  () => logger.info(
                    '''If you have not yet initialized your app, run ${lightCyan.wrap('sankofa init')} to get started.''',
                  ),
                ]);
              },
            );
          });

          group("when pubspec.yaml doesn't contain "
              'sankofa.yaml as an asset', () {
            setUp(() {
              when(() => sankofaEnv.hasSankofaYaml).thenReturn(true);
              when(
                () => sankofaEnv.pubspecContainsSankofaYaml,
              ).thenReturn(false);
            });

            test(
              '''prints error message and throws SankofaNotInitializedException''',
              () async {
                await expectLater(
                  runWithOverrides(
                    () => sankofaValidator.validatePreconditions(
                      checkSankofaInitialized: true,
                    ),
                  ),
                  throwsA(isA<SankofaNotInitializedException>()),
                );
                verifyInOrder([
                  () => logger.err(
                    '''Your pubspec.yaml does not have sankofa.yaml as a flutter asset.''',
                  ),
                  () => logger.info('''
To fix, update your pubspec.yaml to include the following:

  flutter:
    assets:
      - sankofa.yaml # Add this line
'''),
                ]);
              },
            );
          });
        },
      );

      test('throws ValidationFailedException if validator fails', () async {
        final issue = ValidationIssue(
          message: 'test issue',
          severity: ValidationIssueSeverity.error,
          fix: () async {},
        );
        when(() => validator.canRunInCurrentContext()).thenReturn(true);
        when(() => validator.validate()).thenAnswer((_) async => [issue]);
        await expectLater(
          runWithOverrides(
            () => sankofaValidator.validatePreconditions(
              validators: [validator],
            ),
          ),
          throwsA(isA<ValidationFailedException>()),
        );
        verify(() => validator.validate()).called(1);
        verify(
          () => logger.err('Aborting due to validation errors.'),
        ).called(1);
        verify(
          () => logger.info('${red.wrap('[✗]')} ${issue.message}'),
        ).called(1);
        verify(
          () => logger.info(
            '''1 issue can be fixed automatically with ${lightCyan.wrap('sankofa doctor --fix')}.''',
          ),
        ).called(1);
      });

      test(
        '''throws UnsupportedContextException if validator cannot be run in current context''',
        () async {
          const errorMessage = 'Cannot run in this context';
          when(() => validator.canRunInCurrentContext()).thenReturn(false);
          when(
            () => validator.incorrectContextMessage,
          ).thenReturn(errorMessage);
          await expectLater(
            runWithOverrides(
              () => sankofaValidator.validatePreconditions(
                validators: [validator],
              ),
            ),
            throwsA(isA<UnsupportedContextException>()),
          );
          verify(() => logger.err(errorMessage)).called(1);
        },
      );
    });

    group('validateFlavors', () {
      late SankofaYaml sankofaYaml;

      setUp(() {
        when(
          () => sankofaEnv.getSankofaYaml(),
        ).thenAnswer((_) => sankofaYaml);

        when(() => platform.isWindows).thenReturn(false);
        when(() => platform.isLinux).thenReturn(false);
      });

      group('when sankofa.yaml has flavors', () {
        setUp(() {
          sankofaYaml = const SankofaYaml(
            appId: 'test',
            flavors: {'flavorA': 'flavorA'},
          );
        });

        setUp(() {
          when(() => sankofaEnv.getSankofaYaml()).thenReturn(sankofaYaml);
        });

        group('when platform does not support flavors', () {
          group('when a flavor arg is provided', () {
            test('validation fails', () async {
              await expectLater(
                runWithOverrides(
                  () => sankofaValidator.validateFlavors(
                    flavorArg: 'flavorA',
                    releasePlatform: ReleasePlatform.windows,
                  ),
                ),
                throwsA(isA<ValidationFailedException>()),
              );

              verify(
                () => logger.err('Flavors are not supported on this platform.'),
              ).called(1);
              verify(
                () => logger.info(
                  '''Please re-run this command without the --flavor argument. The app id ${lightCyan.wrap('test')} will be used.''',
                ),
              ).called(1);
            });
          });

          group('when no flavor arg is provided', () {
            test('passes validation', () async {
              await expectLater(
                runWithOverrides(
                  () => sankofaValidator.validateFlavors(
                    flavorArg: null,
                    releasePlatform: ReleasePlatform.windows,
                  ),
                ),
                completes,
              );
            });
          });
        });

        group('when platform supports flavors', () {
          group('when no flavor is specified', () {
            test('logs warning and fails validation', () async {
              await expectLater(
                runWithOverrides(
                  () => sankofaValidator.validateFlavors(
                    flavorArg: null,
                    releasePlatform: ReleasePlatform.android,
                  ),
                ),
                completes,
              );
              verify(
                () => logger.warn(
                  '''
The project has flavors (flavorA), but no --flavor argument was provided.
The default app id test will be used.''',
                ),
              ).called(1);
            });
          });

          group('when a flavor arg is provided that exists in the project', () {
            test('passes validation', () async {
              await expectLater(
                runWithOverrides(
                  () => sankofaValidator.validateFlavors(
                    flavorArg: 'flavorA',
                    releasePlatform: ReleasePlatform.android,
                  ),
                ),
                completes,
              );
            });
          });
        });
      });

      group('when sankofa.yaml does not have flavors', () {
        setUp(() {
          sankofaYaml = const SankofaYaml(appId: 'test');
        });

        group('when no flavor arg is provided', () {
          test('passes validation', () async {
            await expectLater(
              runWithOverrides(
                () => sankofaValidator.validateFlavors(
                  flavorArg: null,
                  releasePlatform: ReleasePlatform.android,
                ),
              ),
              completes,
            );
          });

          group('when a flavor arg is provided', () {
            test('fails validation', () async {
              await expectLater(
                runWithOverrides(
                  () => sankofaValidator.validateFlavors(
                    flavorArg: 'flavorA',
                    releasePlatform: ReleasePlatform.android,
                  ),
                ),
                throwsA(isA<ValidationFailedException>()),
              );
            });
          });
        });
      });
    });
  });
}
