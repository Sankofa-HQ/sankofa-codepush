import 'package:mason_logger/mason_logger.dart';
import 'package:sankofa_cli/src/auth/auth.dart';
import 'package:sankofa_cli/src/logging/logging.dart';
import 'package:sankofa_cli/src/sankofa_command.dart';

/// {@template logout_command}
///
/// `sankofa logout`
/// Logout of the current Sankofa user.
/// {@endtemplate}
class LogoutCommand extends SankofaCommand {
  @override
  String get description => 'Logout of the current Sankofa user.';

  @override
  String get name => 'logout';

  @override
  Future<int> run() async {
    if (!auth.isAuthenticated) {
      logger.info('You are already logged out.');
      return ExitCode.success.code;
    }

    final logoutProgress = logger.progress('Logging out of sankofa.dev');
    await auth.logout();
    logoutProgress.complete();

    logger.info('${lightGreen.wrap('You are now logged out.')}');

    return ExitCode.success.code;
  }
}
