import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:sankofa_cli/src/common_arguments.dart';
import 'package:sankofa_cli/src/config/sankofa_yaml.dart';
import 'package:sankofa_cli/src/extensions/arg_results.dart';
import 'package:sankofa_cli/src/interactive_mode.dart' as interactive_mode;
import 'package:sankofa_cli/src/json_output.dart';
import 'package:sankofa_cli/src/sankofa_cli_command_runner.dart';
import 'package:sankofa_cli/src/sankofa_env.dart';
import 'package:sankofa_cli/src/sankofa_validator.dart';
import 'package:sankofa_code_push_client/sankofa_code_push_client.dart';

/// Signature for a function which takes a list of bytes and returns a hash.
typedef HashFunction = String Function(List<int> bytes);

/// Signature for a function which takes a path to a zip file.
typedef UnzipFn = Future<void> Function(String zipFilePath, String outputDir);

/// Signature for a function which builds a [CodePushClient].
typedef CodePushClientBuilder =
    CodePushClient Function({required http.Client httpClient, Uri? hostedUri});

/// Signature for a function which starts a process (e.g. [Process.start]).
typedef StartProcess =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      bool runInShell,
    });

/// {@template sankofa_command}
/// A command in the Sankofa CLI.
/// {@endtemplate}
abstract class SankofaCommand extends Command<int> {
  // We don't currently have a test involving both a CommandRunner
  // and a Command, so we can't test this getter.
  // coverage:ignore-start
  @override
  SankofaCliCommandRunner? get runner =>
      testRunner ?? super.runner as SankofaCliCommandRunner?;
  // coverage:ignore-end

  /// [ArgResults] used for testing purposes only.
  @visibleForTesting
  ArgResults? testArgResults;

  /// The parent command runner used for testing purposes only.
  @visibleForTesting
  SankofaCliCommandRunner? testRunner;

  /// [ArgResults] for the current command.
  ArgResults get results => testArgResults ?? argResults!;

  /// Whether the `--json` global flag was passed.
  ///
  /// Reads from the [isJsonModeRef] scoped dependency, which is set by the
  /// command runner based on the parsed `--json` flag.
  bool get isJsonMode => read(isJsonModeRef);

  // isInteractive is a thin wrapper around the top-level getter in
  // `interactive_mode.dart`, which is directly tested via the runner's
  // "interactive mode" matrix. Exercising it through a SankofaCommand
  // subclass would just re-run the same predicate with no additional value.
  // coverage:ignore-start
  /// Whether the CLI is running in an interactive context.
  ///
  /// `false` when stdout is not a terminal or when `--json` was passed.
  /// See [interactive_mode.isInteractive].
  bool get isInteractive => interactive_mode.isInteractive;
  // coverage:ignore-end

  /// The full command name including parent commands (e.g. "releases list").
  String get fullCommandName {
    final parts = <String>[];
    Command<int>? current = this;
    while (current != null) {
      parts.insert(0, current.name);
      current = current.parent;
    }
    return parts.join(' ');
  }

  /// Emits a JSON success envelope with the given [data] to stdout.
  ///
  /// Only call this when [isJsonMode] is true.
  void emitJsonSuccess(Map<String, dynamic> data) {
    JsonResult.success(data: data, command: fullCommandName).write();
  }

  /// Suffix appended to command descriptions to advertise `--json` mode.
  ///
  /// [example] should be a complete example invocation, e.g.:
  ///   `'sankofa releases list --app-id <id> --json'`
  static String jsonHint(String example) =>
      'Pass --json (global flag) for machine-readable output with all fields:\n'
      '  $example';

  /// Resolves the app ID from `--app-id` or `sankofa.yaml`, validating
  /// preconditions in the process.
  ///
  /// Returns `(appId: <id>, errorCode: null)` on success, or
  /// `(appId: '', errorCode: <code>)` if precondition validation failed.
  Future<({String appId, int? errorCode})> resolveAppId() async {
    final explicitAppId = results[CommonArguments.appIdArg.name] as String?;
    try {
      await sankofaValidator.validatePreconditions(
        checkUserIsAuthenticated: true,
        checkSankofaInitialized: explicitAppId == null,
      );
    } on PreconditionFailedException catch (error) {
      return (appId: '', errorCode: error.exitCode.code);
    }
    final flavor = results.findOption(
      CommonArguments.flavorArg.name,
      argParser: argParser,
    );
    final appId =
        explicitAppId ??
        sankofaEnv.getSankofaYaml()!.getAppId(flavor: flavor);
    return (appId: appId, errorCode: null);
  }

  /// Emits a JSON error envelope to stdout.
  ///
  /// Only call this when [isJsonMode] is true.
  void emitJsonError({
    required JsonErrorCode code,
    required String message,
    String? hint,
  }) {
    JsonResult.error(
      code: code,
      message: message,
      hint: hint,
      command: fullCommandName,
    ).write();
  }
}

/// {@template sankofa_proxy_command}
/// A command in the Sankofa CLI that proxies to an underlying process.
/// {@endtemplate}
abstract class SankofaProxyCommand extends SankofaCommand {
  @override
  ArgParser get argParser => ArgParser.allowAnything();
}
