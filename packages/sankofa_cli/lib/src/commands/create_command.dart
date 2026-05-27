import 'dart:async';

import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:sankofa_cli/src/sankofa_command.dart';
import 'package:sankofa_cli/src/sankofa_env.dart';
import 'package:sankofa_cli/src/sankofa_process.dart';
import 'package:sankofa_cli/src/sankofa_validator.dart';

/// {@template sankofa_create_command}
/// `sankofa create`
/// Create a new Flutter app with Sankofa.
/// {@endtemplate}
class CreateCommand extends SankofaProxyCommand {
  @override
  String get name => 'create';

  @override
  String get description => 'Create a new Flutter project with Sankofa.';

  @override
  Future<int> run() async {
    try {
      await sankofaValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
      );
    } on PreconditionFailedException catch (e) {
      return e.exitCode.code;
    }

    final createExitCode = await process.stream('flutter', [
      'create',
      ...results.rest,
    ]);

    if (createExitCode != ExitCode.success.code) {
      return createExitCode;
    }

    if (results.rest.contains('-h') || results.rest.contains('--help')) {
      return createExitCode;
    }

    return runScoped(
      () => runner!.run(['init']),
      values: {
        sankofaEnvRef.overrideWith(
          () => SankofaEnv(
            flutterProjectRootOverride: p.absolute(
              p.normalize(results.rest.first),
            ),
          ),
        ),
      },
    );
  }
}
