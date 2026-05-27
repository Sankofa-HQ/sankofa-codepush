import 'dart:io';

import 'package:scoped_deps/scoped_deps.dart';
import 'package:sankofa_cli/src/abi.dart';
import 'package:sankofa_cli/src/android_sdk.dart';
import 'package:sankofa_cli/src/android_studio.dart';
import 'package:sankofa_cli/src/artifact_builder/artifact_builder.dart';
import 'package:sankofa_cli/src/artifact_builder/build_trace_session.dart';
import 'package:sankofa_cli/src/artifact_builder/sankofa_tracer.dart';
import 'package:sankofa_cli/src/artifact_manager.dart';
import 'package:sankofa_cli/src/auth/auth.dart';
import 'package:sankofa_cli/src/cache.dart';
import 'package:sankofa_cli/src/checksum_checker.dart';
import 'package:sankofa_cli/src/code_push_client_wrapper.dart';
import 'package:sankofa_cli/src/code_signer.dart';
import 'package:sankofa_cli/src/doctor.dart';
import 'package:sankofa_cli/src/engine_config.dart';
import 'package:sankofa_cli/src/executables/executables.dart';
import 'package:sankofa_cli/src/http_client/http_client.dart';
import 'package:sankofa_cli/src/logging/logging.dart';
import 'package:sankofa_cli/src/network_checker.dart';
import 'package:sankofa_cli/src/os/os.dart';
import 'package:sankofa_cli/src/patch_diff_checker.dart';
import 'package:sankofa_cli/src/platform.dart';
import 'package:sankofa_cli/src/platform/platform.dart';
import 'package:sankofa_cli/src/pubspec_editor.dart';
import 'package:sankofa_cli/src/sankofa_android_artifacts.dart';
import 'package:sankofa_cli/src/sankofa_artifacts.dart';
import 'package:sankofa_cli/src/sankofa_cli_command_runner.dart';
import 'package:sankofa_cli/src/sankofa_env.dart';
import 'package:sankofa_cli/src/sankofa_flutter.dart';
import 'package:sankofa_cli/src/sankofa_process.dart';
import 'package:sankofa_cli/src/sankofa_validator.dart';
import 'package:sankofa_cli/src/sankofa_version.dart';

Future<void> main(List<String> args) async {
  final commandStartedAt = DateTime.now();
  final loggingStdout = runScoped(
    () => LoggingStdout(baseStdOut: stdout, logFile: currentRunLogFile),
    values: {sankofaEnvRef},
  );
  final loggingStderr = runScoped(
    () => LoggingStdout(baseStdOut: stderr, logFile: currentRunLogFile),
    values: {sankofaEnvRef},
  );

  // Write the current command to the top of the log file.
  currentRunLogFile.writeAsStringSync('''
Command: sankofa ${args.join(' ')}

''', mode: FileMode.append);

  await IOOverrides.runZoned(
    () async => _flushThenExit(
      await runScoped(
        () async => SankofaCliCommandRunner().run(args),
        values: {
          abiRef,
          adbRef,
          androidSdkRef,
          androidStudioRef,
          aotToolsRef,
          appleRef,
          artifactBuilderRef,
          artifactManagerRef,
          buildTraceSessionRef.overrideWith(
            () => BuildTraceSession(commandStartedAt: commandStartedAt),
          ),
          authRef,
          bundletoolRef,
          cacheRef,
          checksumCheckerRef,
          codePushClientWrapperRef,
          codeSignerRef,
          devicectlRef,
          diffRef,
          dittoRef,
          doctorRef,
          engineConfigRef,
          gitRef,
          gradlewRef,
          httpClientRef,
          idevicesyslogRef,
          iosDeployRef,
          javaRef,
          linuxRef,
          loggerRef,
          networkCheckerRef,
          openRef,
          osInterfaceRef,
          patchExecutableRef,
          patchDiffCheckerRef,
          platformRef,
          powershellRef,
          processRef,
          pubspecEditorRef,
          sankofaAndroidArtifactsRef,
          sankofaArtifactsRef,
          sankofaEnvRef,
          sankofaFlutterRef,
          sankofaTracerRef,
          sankofaToolsRef,
          sankofaValidatorRef,
          sankofaVersionRef,
          windowsRef,
          xcodeBuildRef,
        },
      ),
    ),
    stdout: () => loggingStdout,
    stderr: () => loggingStderr,
  );
}

/// Flushes the stdout and stderr streams, then exits the program with the given
/// status code.
///
/// This returns a Future that will never complete, since the program will have
/// exited already. This is useful to prevent Future chains from proceeding
/// after you've decided to exit.
Future<void> _flushThenExit(int status) {
  return Future.wait<void>([
    stdout.close(),
    stderr.close(),
  ]).then<void>((_) => exit(status));
}
