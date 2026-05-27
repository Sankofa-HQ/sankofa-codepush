import 'package:sankofa_cli/src/commands/account/account.dart';
import 'package:sankofa_cli/src/sankofa_command.dart';

/// {@template account_command}
/// Commands for inspecting the current Sankofa account.
/// {@endtemplate}
class AccountCommand extends SankofaCommand {
  /// {@macro account_command}
  AccountCommand() {
    addSubcommand(AppsCommand());
    addSubcommand(OrgsCommand());
    addSubcommand(WhoamiCommand());
  }

  @override
  String get name => 'account';

  @override
  String get description => 'Manage your Sankofa account.';
}
