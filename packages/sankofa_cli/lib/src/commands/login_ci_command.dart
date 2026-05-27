import 'package:mason_logger/mason_logger.dart';
import 'package:sankofa_cli/src/logging/logging.dart';
import 'package:sankofa_cli/src/sankofa_command.dart';

/// {@template login_ci_command}
/// `sankofa login:ci`
/// Removed — directs users to API keys instead.
/// {@endtemplate}
class LoginCiCommand extends SankofaCommand {
  @override
  String get description => 'Removed — use API keys instead.';

  @override
  String get name => 'login:ci';

  @override
  Future<int> run() async {
    logger.err(
      '''
sankofa login:ci has been replaced by API keys.

Create an API key at ${link(uri: Uri.parse('https://console.sankofa.dev'))} and set it as your ${lightCyan.wrap('SANKOFA_TOKEN')} environment variable.

Learn more: ${link(uri: Uri.parse('https://docs.sankofa.dev/account/api-keys/'))}''',
    );
    return ExitCode.usage.code;
  }
}
