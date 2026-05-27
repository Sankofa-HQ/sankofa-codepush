import 'dart:io';

import 'package:sankofa_cli/src/sankofa_version.dart';
import 'package:sankofa_cli/src/validators/validators.dart';

/// Verifies that the currently installed version of Sankofa is the latest.
class SankofaVersionValidator extends Validator {
  /// Creates a new [SankofaVersionValidator].
  SankofaVersionValidator();

  @override
  String get description => 'Sankofa is up-to-date';

  @override
  Future<List<ValidationIssue>> validate() async {
    final bool isSankofaUpToDate;

    try {
      isSankofaUpToDate = await sankofaVersion.isLatest();
    } on ProcessException catch (e) {
      return [
        ValidationIssue(
          severity: ValidationIssueSeverity.error,
          message: 'Failed to get sankofa version. Error: ${e.message}',
        ),
      ];
    }

    if (!isSankofaUpToDate) {
      return [
        const ValidationIssue(
          severity: ValidationIssueSeverity.warning,
          message: '''
A new version of sankofa is available! Run `sankofa upgrade` to upgrade.''',
        ),
      ];
    }

    return [];
  }
}
