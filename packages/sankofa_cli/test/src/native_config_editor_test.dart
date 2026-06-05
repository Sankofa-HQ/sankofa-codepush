// cspell:words plist plists

import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:sankofa_cli/src/config/sankofa_yaml.dart';
import 'package:sankofa_cli/src/native_config_editor.dart';
import 'package:sankofa_cli/src/sankofa_env.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:test/test.dart';

import 'mocks.dart';

class _FakeDirectory extends Fake implements Directory {}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeDirectory());
  });

  group(NativeConfigEditor, () {
    late SankofaEnv sankofaEnv;
    late NativeConfigEditor editor;
    late Directory tempDir;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {sankofaEnvRef.overrideWith(() => sankofaEnv)},
      );
    }

    setUp(() {
      sankofaEnv = MockSankofaEnv();
      editor = NativeConfigEditor();
      tempDir = Directory.systemTemp.createTempSync('native_config_editor_');
      when(() => sankofaEnv.getFlutterProjectRoot()).thenReturn(tempDir);
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    SankofaYaml configWithBaseUrl({String? baseUrl}) => SankofaYaml(
      appId: 'proj_test_app_id',
      baseUrl: baseUrl ?? 'https://example.test',
    );

    group('syncAndroidManifestMetadata', () {
      late File manifest;

      const baseManifest = r'''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET"/>
    <application
        android:label="hello"
        android:name="${applicationName}"
        android:icon="@mipmap/ic_launcher">
        <activity android:name=".MainActivity"/>
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
</manifest>
''';

      setUp(() {
        final manifestDir = Directory(
          p.join(tempDir.path, 'android', 'app', 'src', 'main'),
        )..createSync(recursive: true);
        manifest = File(p.join(manifestDir.path, 'AndroidManifest.xml'))
          ..writeAsStringSync(baseManifest);
      });

      test('returns empty + no edits when manifest is missing', () {
        manifest.deleteSync();
        final result = runWithOverrides(
          () => editor.syncAndroidManifestMetadata(config: configWithBaseUrl()),
        );
        expect(result, isEmpty);
      });

      test('inserts both app_id and base_url meta-data on first run', () {
        final result = runWithOverrides(
          () => editor.syncAndroidManifestMetadata(config: configWithBaseUrl()),
        );
        expect(result, [
          'dev.sankofa.code_push.app_id',
          'dev.sankofa.code_push.base_url',
        ]);
        final contents = manifest.readAsStringSync();
        expect(
          contents,
          contains('android:name="dev.sankofa.code_push.app_id"'),
        );
        expect(contents, contains('android:value="proj_test_app_id"'));
        expect(
          contents,
          contains('android:name="dev.sankofa.code_push.base_url"'),
        );
        expect(contents, contains('android:value="https://example.test"'));
      });

      test('inserts only app_id when base_url is null', () {
        const config = SankofaYaml(appId: 'proj_only');
        final result = runWithOverrides(
          () => editor.syncAndroidManifestMetadata(config: config),
        );
        expect(result, ['dev.sankofa.code_push.app_id']);
        expect(
          manifest.readAsStringSync(),
          isNot(contains('dev.sankofa.code_push.base_url')),
        );
      });

      test('is idempotent — no changes on second run', () {
        runWithOverrides(
          () => editor.syncAndroidManifestMetadata(config: configWithBaseUrl()),
        );
        final afterFirst = manifest.readAsStringSync();
        final secondResult = runWithOverrides(
          () => editor.syncAndroidManifestMetadata(config: configWithBaseUrl()),
        );
        expect(secondResult, isEmpty);
        expect(manifest.readAsStringSync(), equals(afterFirst));
      });

      test('updates existing value when sankofa.yaml has changed', () {
        runWithOverrides(
          () => editor.syncAndroidManifestMetadata(config: configWithBaseUrl()),
        );
        final updatedResult = runWithOverrides(
          () => editor.syncAndroidManifestMetadata(
            config: configWithBaseUrl(baseUrl: 'https://updated.test'),
          ),
        );
        expect(updatedResult, ['dev.sankofa.code_push.base_url']);
        final contents = manifest.readAsStringSync();
        expect(contents, contains('android:value="https://updated.test"'));
        expect(contents, isNot(contains('https://example.test')));
      });

      test('preserves a malformed manifest by returning empty', () {
        manifest.writeAsStringSync('not <valid> </xml>');
        final result = runWithOverrides(
          () => editor.syncAndroidManifestMetadata(config: configWithBaseUrl()),
        );
        expect(result, isEmpty);
      });
    });

    group('syncIosInfoPlist', () {
      late File plist;

      const basePlist = '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDisplayName</key>
	<string>Hello</string>
	<key>CFBundleIdentifier</key>
	<string>com.example.hello</string>
</dict>
</plist>
''';

      setUp(() {
        final plistDir = Directory(p.join(tempDir.path, 'ios', 'Runner'))
          ..createSync(recursive: true);
        plist = File(p.join(plistDir.path, 'Info.plist'))
          ..writeAsStringSync(basePlist);
      });

      test('returns empty + no edits when plist is missing', () {
        plist.deleteSync();
        final result = runWithOverrides(
          () => editor.syncIosInfoPlist(config: configWithBaseUrl()),
        );
        expect(result, isEmpty);
      });

      test('inserts both keys on first run', () {
        final result = runWithOverrides(
          () => editor.syncIosInfoPlist(config: configWithBaseUrl()),
        );
        expect(result, ['SankofaCodePushAppId', 'SankofaCodePushBaseURL']);
        final contents = plist.readAsStringSync();
        expect(contents, contains('<key>SankofaCodePushAppId</key>'));
        expect(contents, contains('<string>proj_test_app_id</string>'));
        expect(contents, contains('<key>SankofaCodePushBaseURL</key>'));
        expect(contents, contains('<string>https://example.test</string>'));
      });

      test('inserts only app_id when base_url is null', () {
        const config = SankofaYaml(appId: 'proj_only');
        final result = runWithOverrides(
          () => editor.syncIosInfoPlist(config: config),
        );
        expect(result, ['SankofaCodePushAppId']);
        expect(
          plist.readAsStringSync(),
          isNot(contains('SankofaCodePushBaseURL')),
        );
      });

      test('is idempotent — no changes on second run', () {
        runWithOverrides(
          () => editor.syncIosInfoPlist(config: configWithBaseUrl()),
        );
        final afterFirst = plist.readAsStringSync();
        final secondResult = runWithOverrides(
          () => editor.syncIosInfoPlist(config: configWithBaseUrl()),
        );
        expect(secondResult, isEmpty);
        expect(plist.readAsStringSync(), equals(afterFirst));
      });

      test('updates existing value when sankofa.yaml has changed', () {
        runWithOverrides(
          () => editor.syncIosInfoPlist(config: configWithBaseUrl()),
        );
        final updatedResult = runWithOverrides(
          () => editor.syncIosInfoPlist(
            config: configWithBaseUrl(baseUrl: 'https://changed.test'),
          ),
        );
        expect(updatedResult, ['SankofaCodePushBaseURL']);
        final contents = plist.readAsStringSync();
        expect(contents, contains('<string>https://changed.test</string>'));
        expect(contents, isNot(contains('https://example.test')));
      });

      test('escapes XML entities in values', () {
        const config = SankofaYaml(
          appId: 'proj_<weird>&"value"',
          baseUrl: 'https://example.test/path?a=b&c=d',
        );
        runWithOverrides(
          () => editor.syncIosInfoPlist(config: config),
        );
        final contents = plist.readAsStringSync();
        expect(
          contents,
          contains(
            'proj_&lt;weird&gt;&amp;"value"',
          ),
        );
        expect(contents, contains('a=b&amp;c=d'));
      });
    });

    group('removeLegacyYamlAssetEntry', () {
      late File pubspec;

      setUp(() {
        pubspec = File(p.join(tempDir.path, 'pubspec.yaml'));
        when(
          () => sankofaEnv.getPubspecYamlFile(cwd: any(named: 'cwd')),
        ).thenReturn(pubspec);
      });

      test('returns false when no pubspec exists', () {
        final result = runWithOverrides(editor.removeLegacyYamlAssetEntry);
        expect(result, isFalse);
      });

      test('returns false when sankofa.yaml is not an asset', () {
        pubspec.writeAsStringSync('''
name: test
flutter:
  assets:
    - images/foo.png
''');
        final result = runWithOverrides(editor.removeLegacyYamlAssetEntry);
        expect(result, isFalse);
        expect(
          pubspec.readAsStringSync(),
          contains('- images/foo.png'),
        );
      });

      test('removes the asset entry and returns true', () {
        pubspec.writeAsStringSync('''
name: test
flutter:
  assets:
    - sankofa.yaml
    - images/foo.png
''');
        final result = runWithOverrides(editor.removeLegacyYamlAssetEntry);
        expect(result, isTrue);
        final contents = pubspec.readAsStringSync();
        expect(contents, isNot(contains('- sankofa.yaml')));
        expect(contents, contains('- images/foo.png'));
      });

      test('is idempotent — second call returns false', () {
        pubspec.writeAsStringSync('''
name: test
flutter:
  assets:
    - sankofa.yaml
''');
        final first = runWithOverrides(editor.removeLegacyYamlAssetEntry);
        final second = runWithOverrides(editor.removeLegacyYamlAssetEntry);
        expect(first, isTrue);
        expect(second, isFalse);
      });
    });
  });
}
