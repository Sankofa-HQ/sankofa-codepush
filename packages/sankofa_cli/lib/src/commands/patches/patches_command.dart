import 'package:sankofa_cli/src/commands/patches/patches.dart';
import 'package:sankofa_cli/src/sankofa_command.dart';

/// {@template patches_command}
/// Commands for managing Sankofa patches.
/// {@endtemplate}
class PatchesCommand extends SankofaCommand {
  /// {@macro patches_command}
  PatchesCommand() {
    addSubcommand(PatchesInfoCommand());
    addSubcommand(PatchesListCommand());
    addSubcommand(PromoteCommand());
    addSubcommand(SetTrackCommand());
  }

  @override
  String get name => 'patches';

  @override
  String get description => 'Manage Sankofa patches.';
}
