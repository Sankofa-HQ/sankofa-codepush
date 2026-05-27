import 'package:args/command_runner.dart';
import 'package:sankofa_ci/src/commands/commands.dart';

/// The sankofa_ci command runner.
class SankofaCiCommandRunner extends CommandRunner<int> {
  /// Creates a [SankofaCiCommandRunner].
  SankofaCiCommandRunner()
    : super('sankofa_ci', 'CI tooling for Dart/Flutter monorepos') {
    addCommand(AffectedPackagesCommand());
    addCommand(FlutterVersionCommand());
    addCommand(GenerateCommand());
    addCommand(UpdateActionsCommand());
    addCommand(VerifyCommand());
  }
}
