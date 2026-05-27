import 'package:sankofa_cli/src/commands/commands.dart';
import 'package:sankofa_cli/src/sankofa_command.dart';

/// {@template cache_command}
/// `sankofa cache`
/// Manage the Sankofa cache.
/// {@endtemplate}
class CacheCommand extends SankofaCommand {
  /// {@macro cache_command}
  CacheCommand() {
    addSubcommand(CleanCacheCommand());
  }

  @override
  String get description => 'Manage the Sankofa cache.';

  @override
  String get name => 'cache';
}
