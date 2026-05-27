import 'package:sankofa_cli/src/commands/commands.dart';
import 'package:sankofa_cli/src/sankofa_command.dart';

/// {@template flutter_versions_command}
/// `sankofa flutter versions`
/// Manage your Sankofa Flutter versions.
/// {@endtemplate}
class FlutterVersionsCommand extends SankofaCommand {
  /// {@macro flutter_versions_command}
  FlutterVersionsCommand() {
    addSubcommand(FlutterVersionsListCommand());
  }

  @override
  String get description => 'Manage your Sankofa Flutter versions.';

  @override
  String get name => 'versions';
}
