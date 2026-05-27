import 'package:sankofa_cli/src/commands/commands.dart';
import 'package:sankofa_cli/src/sankofa_command.dart';

/// {@template flutter_command}
/// `sankofa flutter`
/// Manage your Sankofa Flutter installation.
/// {@endtemplate}
class FlutterCommand extends SankofaCommand {
  /// {@macro flutter_command}
  FlutterCommand() {
    addSubcommand(FlutterVersionsCommand());
    addSubcommand(FlutterConfigCommand());
  }

  @override
  String get description => 'Manage your Sankofa Flutter installation.';

  @override
  String get name => 'flutter';
}
