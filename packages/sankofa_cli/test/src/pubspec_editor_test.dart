import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:scoped_deps/scoped_deps.dart';
import 'package:sankofa_cli/src/pubspec_editor.dart';
import 'package:sankofa_cli/src/sankofa_env.dart';
import 'package:test/test.dart';

import 'mocks.dart';

class _FakeDirectory extends Fake implements Directory {}

void main() {
  group(PubspecEditor, () {
    late SankofaEnv sankofaEnv;
    late PubspecEditor pubspecEditor;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {sankofaEnvRef.overrideWith(() => sankofaEnv)},
      );
    }

    setUpAll(() {
      registerFallbackValue(_FakeDirectory());
    });

    setUp(() {
      sankofaEnv = MockSankofaEnv();
      pubspecEditor = PubspecEditor();
    });

    group('addSankofaYamlToPubspecAssets', () {
      group('when sankofa.yaml is part of the pubspec.yaml assets', () {
        setUp(() {
          when(
            () => sankofaEnv.pubspecContainsSankofaYaml,
          ).thenReturn(true);
        });

        test('does nothing', () {
          expect(
            () =>
                runWithOverrides(pubspecEditor.addSankofaYamlToPubspecAssets),
            returnsNormally,
          );
          verifyNever(() => sankofaEnv.getFlutterProjectRoot());
        });
      });

      group('when sankofa.yaml is not part of the pubspec.yaml assets', () {
        setUp(() {
          when(
            () => sankofaEnv.pubspecContainsSankofaYaml,
          ).thenReturn(false);
        });

        group('when a flutter project root cannot be found', () {
          setUp(() {
            when(() => sankofaEnv.getFlutterProjectRoot()).thenReturn(null);
          });

          test('does nothing', () {
            expect(
              () => runWithOverrides(
                pubspecEditor.addSankofaYamlToPubspecAssets,
              ),
              returnsNormally,
            );
            verify(() => sankofaEnv.getFlutterProjectRoot()).called(1);
          });
        });

        group('when a flutter project root can be found', () {
          const basePubspecContents = '''
name: test
version: 1.0.0
environment:
 sdk: ">=2.19.0 <3.0.0"''';
          late Directory tempDir;
          late File pubspecFile;

          setUp(() {
            tempDir = Directory.systemTemp.createTempSync();
            pubspecFile = File(p.join(tempDir.path, 'pubspec.yaml'));
            when(
              () => sankofaEnv.getFlutterProjectRoot(),
            ).thenReturn(tempDir);
            when(
              () => sankofaEnv.getPubspecYamlFile(cwd: any(named: 'cwd')),
            ).thenReturn(pubspecFile);
          });

          test('creates flutter.assets and adds sankofa.yaml', () {
            pubspecFile
              ..createSync()
              ..writeAsStringSync(basePubspecContents);
            IOOverrides.runZoned(
              () => runWithOverrides(
                pubspecEditor.addSankofaYamlToPubspecAssets,
              ),
              getCurrentDirectory: () => tempDir,
            );
            expect(
              pubspecFile.readAsStringSync(),
              equals('''
$basePubspecContents
flutter:
 assets:
   - sankofa.yaml
'''),
            );
          });

          test('creates assets and adds sankofa.yaml (empty flutter)', () {
            pubspecFile
              ..createSync()
              ..writeAsStringSync('''
$basePubspecContents
flutter:
''');
            IOOverrides.runZoned(
              () => runWithOverrides(
                pubspecEditor.addSankofaYamlToPubspecAssets,
              ),
              getCurrentDirectory: () => tempDir,
            );
            expect(
              pubspecFile.readAsStringSync(),
              equals('''
$basePubspecContents
flutter:
 assets:
   - sankofa.yaml
'''),
            );
          });
          test(
            'creates assets and adds sankofa.yaml (non-empty flutter)',
            () {
              pubspecFile
                ..createSync()
                ..writeAsStringSync('''
$basePubspecContents
flutter:
 uses-material-design: true
''');
              IOOverrides.runZoned(
                () => runWithOverrides(
                  pubspecEditor.addSankofaYamlToPubspecAssets,
                ),
                getCurrentDirectory: () => tempDir,
              );
              expect(
                pubspecFile.readAsStringSync(),
                equals('''
$basePubspecContents
flutter:
 assets:
  - sankofa.yaml
 uses-material-design: true
'''),
              );
            },
          );
          test('adds sankofa.yaml to assets (existing assets)', () {
            pubspecFile
              ..createSync()
              ..writeAsStringSync('''
$basePubspecContents
flutter:
 assets:
  - some/asset.txt
''');
            IOOverrides.runZoned(
              () => runWithOverrides(
                pubspecEditor.addSankofaYamlToPubspecAssets,
              ),
              getCurrentDirectory: () => tempDir,
            );
            expect(
              pubspecFile.readAsStringSync(),
              equals('''
$basePubspecContents
flutter:
 assets:
  - some/asset.txt
  - sankofa.yaml
'''),
            );
          });
        });
      });
    });
  });
}
