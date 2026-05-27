import 'dart:async';

import 'package:sankofa_cli/src/sankofa_command.dart';
import 'package:sankofa_cli/src/sankofa_process.dart';

/// {@template flutter_config_command}
/// `sankofa flutter config`
/// Manage your Sankofa Flutter Config.
/// {@endtemplate}
class FlutterConfigCommand extends SankofaProxyCommand {
  @override
  String get description =>
      '''Configure Flutter settings. This proxies to the underlying `flutter config` command.''';

  @override
  String get name => 'config';

  @override
  FutureOr<int> run() => process.stream('flutter', ['config', ...results.rest]);
}
