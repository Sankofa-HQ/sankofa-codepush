import 'package:sankofa_cli/src/pubspec_editor.dart';
import 'package:sankofa_cli/src/sankofa_env.dart';
import 'package:sankofa_cli/src/validators/validators.dart';

/// Verifies that the sankofa.yaml is found in pubspec.yaml assets.
class SankofaYamlAssetValidator extends Validator {
  @override
  String get description => 'sankofa.yaml found in pubspec.yaml assets';

  @override
  bool canRunInCurrentContext() => sankofaEnv.hasPubspecYaml;

  @override
  String get incorrectContextMessage => '''
The pubspec.yaml file does not exist.
The command you are running must be run within a Flutter app project.''';

  @override
  Future<List<ValidationIssue>> validate() async {
    if (!canRunInCurrentContext()) {
      return [
        const ValidationIssue(
          severity: ValidationIssueSeverity.error,
          message: 'No pubspec.yaml file found',
        ),
      ];
    }

    if (sankofaEnv.pubspecContainsSankofaYaml) {
      return [];
    }

    return [
      ValidationIssue(
        severity: ValidationIssueSeverity.error,
        message: 'No sankofa.yaml found in pubspec.yaml assets',
        fix: () => pubspecEditor.addSankofaYamlToPubspecAssets(),
      ),
    ];
  }
}
