import 'package:sankofa_cli/src/commands/releases/releases.dart';
import 'package:sankofa_cli/src/sankofa_command.dart';

/// {@template releases_command}
/// Commands for managing Sankofa releases.
/// {@endtemplate}
class ReleasesCommand extends SankofaCommand {
  /// {@macro releases_command}
  ReleasesCommand() {
    addSubcommand(GetApksCommand());
    addSubcommand(ReleasesInfoCommand());
    addSubcommand(ReleasesListCommand());
  }

  @override
  String get name => 'releases';

  @override
  String get description => 'Manage Sankofa releases.';
}
