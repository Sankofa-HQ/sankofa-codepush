import 'package:collection/collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:sankofa_cli/src/auth/auth.dart';
import 'package:sankofa_cli/src/logging/logging.dart';
import 'package:sankofa_cli/src/platform.dart';
import 'package:sankofa_cli/src/pubspec_editor.dart';
import 'package:sankofa_cli/src/sankofa_env.dart';
import 'package:sankofa_cli/src/validators/validators.dart';
import 'package:sankofa_code_push_client/sankofa_code_push_client.dart';

/// An exception thrown when a precondition for running a command is not met.
abstract interface class PreconditionFailedException implements Exception {
  /// The exit code to use when the precondition fails.
  ExitCode get exitCode;
}

/// An exception thrown when Sankofa has not been initialized.
class SankofaNotInitializedException implements PreconditionFailedException {
  @override
  ExitCode get exitCode => ExitCode.config;
}

/// An exception thrown when the user is not authorized to run a command.
class UserNotAuthorizedException implements PreconditionFailedException {
  @override
  ExitCode get exitCode => ExitCode.noUser;
}

/// An exception thrown when validation fails.
class ValidationFailedException implements PreconditionFailedException {
  @override
  ExitCode get exitCode => ExitCode.config;
}

/// An exception thrown when a command is run in an unsupported context.
class UnsupportedContextException implements PreconditionFailedException {
  // coverage:ignore-start
  @override
  ExitCode get exitCode => ExitCode.unavailable;
  // coverage:ignore-end
}

/// An exception thrown when the operating system is not supported.
class UnsupportedOperatingSystemException
    implements PreconditionFailedException {
  @override
  ExitCode get exitCode => ExitCode.unavailable;
}

/// A reference to a [SankofaValidator] instance.
final sankofaValidatorRef = create(SankofaValidator.new);

/// The [SankofaValidator] instance available in the current zone.
SankofaValidator get sankofaValidator => read(sankofaValidatorRef);

/// {@template sankofa_validator}
/// A class that provides common validation functionality for commands.
/// {@endtemplate}
class SankofaValidator {
  /// {@macro sankofa_validator}
  const SankofaValidator();

  /// Checks common preconditions for running a command and throws an
  /// appropriate [PreconditionFailedException] if any of them fail.
  Future<void> validatePreconditions({
    bool checkSankofaInitialized = false,
    bool checkUserIsAuthenticated = false,
    List<Validator> validators = const [],
    Set<String>? supportedOperatingSystems,
  }) async {
    if (supportedOperatingSystems != null &&
        !supportedOperatingSystems.contains(platform.operatingSystem)) {
      logger.err(
        '''This command is only supported on ${supportedOperatingSystems.join(' ,')}.''',
      );
      throw UnsupportedOperatingSystemException();
    }

    if (checkUserIsAuthenticated && !auth.isAuthenticated) {
      logger
        ..err('You must be logged in to run this command.')
        ..info(
          '''If you already have an account, run ${lightCyan.wrap('sankofa login')} to sign in.''',
        )
        ..info(
          '''If you don't have a Sankofa account, go to ${link(uri: Uri.parse('https://console.sankofa.dev'))} to create one.''',
        );
      throw UserNotAuthorizedException();
    }

    if (checkSankofaInitialized) {
      if (!sankofaEnv.hasSankofaYaml) {
        logger
          ..err(
            '''Unable to find sankofa.yaml. Are you in a sankofa app directory?''',
          )
          ..info(
            '''If you have not yet initialized your app, run ${lightCyan.wrap('sankofa init')} to get started.''',
          );
        throw SankofaNotInitializedException();
      }

      if (!sankofaEnv.pubspecContainsSankofaYaml) {
        logger
          ..err(
            '''Your pubspec.yaml does not have sankofa.yaml as a flutter asset.''',
          )
          ..info('''
To fix, update your pubspec.yaml to include the following:

  flutter:
    assets:
      - sankofa.yaml # Add this line
''');
        throw SankofaNotInitializedException();
      }

      // The Sankofa-built Flutter engine reads `sankofa.yaml` directly.
      // Ensure it's listed as a Flutter asset so it's bundled into the app.
      // Idempotent.
      pubspecEditor.ensureEngineConfigYamlAsset();
    }

    for (final validator in validators) {
      if (!validator.canRunInCurrentContext()) {
        logger.err(validator.incorrectContextMessage);
        throw UnsupportedContextException();
      }
    }

    final validationIssues = await runValidators(validators);
    if (validationIssuesContainsError(validationIssues)) {
      logValidationFailure(issues: validationIssues);
      throw ValidationFailedException();
    }
  }

  /// Runs [Validator.validate] on all [validators] and writes results to
  /// stdout.
  Future<List<ValidationIssue>> runValidators(
    List<Validator> validators,
  ) async {
    final validationIssues = (await Future.wait(
      validators.map((v) => v.validate()),
    )).flattened.toList();

    for (final issue in validationIssues) {
      logger.info(issue.displayMessage);
    }

    return validationIssues;
  }

  /// Runs [FlavorValidator] and throws a [ValidationFailedException] if any
  /// issues are found.
  Future<void> validateFlavors({
    required String? flavorArg,
    required ReleasePlatform releasePlatform,
  }) async {
    if (!releasePlatform.supportsFlavors) {
      if (flavorArg != null) {
        logger
          ..err('Flavors are not supported on this platform.')
          ..info(
            '''Please re-run this command without the --flavor argument. The app id ${lightCyan.wrap(sankofaEnv.getSankofaYaml()!.appId)} will be used.''',
          );

        throw ValidationFailedException();
      }

      return;
    }

    final flavorValidator = FlavorValidator(flavorArg: flavorArg);
    final issues = await flavorValidator.validate();
    if (validationIssuesContainsError(issues)) {
      for (final issue in issues) {
        logger.err(issue.message);
      }

      throw ValidationFailedException();
    }

    if (validationIssuesContainsWarning(issues)) {
      for (final issue in issues) {
        logger.warn(issue.message);
      }
    }
  }

  /// Whether any [ValidationIssue]s have a severity of
  /// [ValidationIssueSeverity.error].
  bool validationIssuesContainsError(List<ValidationIssue> issues) =>
      issues.any((issue) => issue.severity == ValidationIssueSeverity.error);

  /// Whether any [ValidationIssue]s have a severity of
  /// [ValidationIssueSeverity.warning].
  bool validationIssuesContainsWarning(List<ValidationIssue> issues) =>
      issues.any((issue) => issue.severity == ValidationIssueSeverity.warning);

  /// Logs a message indicating that validation failed. If any of the issues
  /// can be automatically fixed, this also prompts the user to run
  /// `sankofa doctor --fix`.
  void logValidationFailure({required List<ValidationIssue> issues}) {
    logger.err('Aborting due to validation errors.');

    final fixableIssues = issues.where((issue) => issue.fix != null);
    if (fixableIssues.isNotEmpty) {
      logger.info(
        '''${fixableIssues.length} issue${fixableIssues.length == 1 ? '' : 's'} can be fixed automatically with ${lightCyan.wrap('sankofa doctor --fix')}.''',
      );
    }
  }
}
