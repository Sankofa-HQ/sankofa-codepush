import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:sankofa_cli/src/sankofa_version.dart';
import 'package:sankofa_cli/src/validators/validators.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group('SankofaVersionValidator', () {
    late SankofaVersion sankofaVersion;
    late SankofaVersionValidator validator;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {sankofaVersionRef.overrideWith(() => sankofaVersion)},
      );
    }

    setUp(() {
      sankofaVersion = MockSankofaVersion();
      validator = SankofaVersionValidator();

      when(sankofaVersion.isLatest).thenAnswer((_) async => false);
    });

    test('has a non-empty description', () {
      expect(validator.description, isNotEmpty);
    });

    test('canRunInContext always returns true', () {
      expect(validator.canRunInCurrentContext(), isTrue);
    });

    test('returns no issues when sankofa is up-to-date', () async {
      when(sankofaVersion.isLatest).thenAnswer((_) async => true);

      final results = await runWithOverrides(validator.validate);

      expect(results, isEmpty);
    });

    test(
      'returns an error when sankofa version cannot be determined',
      () async {
        when(
          sankofaVersion.isLatest,
        ).thenThrow(const ProcessException('git', ['rev-parse', 'HEAD']));

        final results = await runWithOverrides(validator.validate);

        expect(results, hasLength(1));
        expect(results.first.severity, ValidationIssueSeverity.error);
        expect(
          results.first.message,
          contains('Failed to get sankofa version'),
        );
      },
    );

    test('returns a warning when a newer sankofa is available', () async {
      when(sankofaVersion.isLatest).thenAnswer((_) async => false);

      final results = await runWithOverrides(validator.validate);

      expect(results, hasLength(1));
      expect(results.first.severity, ValidationIssueSeverity.warning);
      expect(
        results.first.message,
        contains('A new version of sankofa is available!'),
      );
    });
  });
}
