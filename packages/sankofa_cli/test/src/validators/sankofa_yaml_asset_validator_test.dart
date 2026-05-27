import 'package:mocktail/mocktail.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:sankofa_cli/src/pubspec_editor.dart';
import 'package:sankofa_cli/src/sankofa_env.dart';
import 'package:sankofa_cli/src/validators/validators.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(SankofaYamlAssetValidator, () {
    late SankofaEnv sankofaEnv;
    late PubspecEditor pubspecEditor;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        body,
        values: {
          sankofaEnvRef.overrideWith(() => sankofaEnv),
          pubspecEditorRef.overrideWith(() => pubspecEditor),
        },
      );
    }

    setUp(() {
      sankofaEnv = MockSankofaEnv();
      pubspecEditor = MockPubspecEditor();
    });

    test('has a non-empty description', () {
      expect(SankofaYamlAssetValidator().description, isNotEmpty);
    });

    test('has a non-empty incorrectContextMessage', () {
      expect(SankofaYamlAssetValidator().incorrectContextMessage, isNotEmpty);
    });

    group('canRunInContext', () {
      test('returns false if no pubspec.yaml file exists', () {
        when(() => sankofaEnv.hasPubspecYaml).thenReturn(false);
        final result = runWithOverrides(
          () => SankofaYamlAssetValidator().canRunInCurrentContext(),
        );
        expect(result, isFalse);
      });

      test('returns true if a pubspec.yaml file exists', () {
        when(() => sankofaEnv.hasPubspecYaml).thenReturn(true);
        final result = runWithOverrides(
          () => SankofaYamlAssetValidator().canRunInCurrentContext(),
        );
        expect(result, isTrue);
      });
    });

    group('validate', () {
      test(
        'returns with no errors if pubspec.yaml has sankofa.yaml in assets',
        () async {
          when(() => sankofaEnv.hasPubspecYaml).thenReturn(true);
          when(
            () => sankofaEnv.pubspecContainsSankofaYaml,
          ).thenReturn(true);
          final results = await runWithOverrides(
            SankofaYamlAssetValidator().validate,
          );
          expect(results.map((res) => res.severity), isEmpty);
        },
      );

      test('returns an error if pubspec.yaml file does not exist', () async {
        when(() => sankofaEnv.hasPubspecYaml).thenReturn(false);
        final results = await runWithOverrides(
          SankofaYamlAssetValidator().validate,
        );
        expect(results, hasLength(1));
        expect(results.first.severity, ValidationIssueSeverity.error);
        expect(results.first.message, startsWith('No pubspec.yaml file found'));
        expect(results.first.fix, isNull);
      });

      test('returns error if sankofa.yaml is missing from assets', () async {
        when(() => sankofaEnv.hasPubspecYaml).thenReturn(true);
        when(() => sankofaEnv.pubspecContainsSankofaYaml).thenReturn(false);
        final results = await runWithOverrides(
          SankofaYamlAssetValidator().validate,
        );
        expect(results, hasLength(1));
        expect(
          results.first,
          equals(
            const ValidationIssue(
              severity: ValidationIssueSeverity.error,
              message: 'No sankofa.yaml found in pubspec.yaml assets',
            ),
          ),
        );
      });
    });

    group('fix', () {
      test('adds sankofa.yaml to pubspec.yaml', () async {
        when(() => sankofaEnv.hasPubspecYaml).thenReturn(true);
        when(() => sankofaEnv.pubspecContainsSankofaYaml).thenReturn(false);
        when(
          () => pubspecEditor.addSankofaYamlToPubspecAssets(),
        ).thenAnswer((_) {});
        final results = await runWithOverrides(
          SankofaYamlAssetValidator().validate,
        );
        expect(results, hasLength(1));
        expect(results.first.fix, isNotNull);
        await runWithOverrides(() => results.first.fix!());
        verify(pubspecEditor.addSankofaYamlToPubspecAssets).called(1);
      });
    });
  });
}
