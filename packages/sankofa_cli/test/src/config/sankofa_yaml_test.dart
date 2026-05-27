import 'package:checked_yaml/checked_yaml.dart';
import 'package:sankofa_cli/src/config/config.dart';
import 'package:test/test.dart';

void main() {
  group('SankofaYaml', () {
    test('can be deserialized without flavors', () {
      const yaml = '''
app_id: test_app_id
base_url: https://example.com
''';
      final sankofaYaml = checkedYamlDecode(
        yaml,
        (m) => SankofaYaml.fromJson(m!),
      );
      expect(sankofaYaml.appId, 'test_app_id');
      expect(sankofaYaml.flavors, isNull);
      expect(sankofaYaml.baseUrl, 'https://example.com');
    });

    test('can be deserialized with flavors', () {
      const yaml = '''
app_id: test_app_id1
flavors:
  development: test_app_id1
  production: test_app_id2
base_url: https://example.com
''';
      final sankofaYaml = checkedYamlDecode(
        yaml,
        (m) => SankofaYaml.fromJson(m!),
      );
      expect(sankofaYaml.appId, equals('test_app_id1'));
      expect(sankofaYaml.flavors, {
        'development': 'test_app_id1',
        'production': 'test_app_id2',
      });
      expect(sankofaYaml.baseUrl, 'https://example.com');
    });

    test('can be deserialized without auto-update', () {
      const yaml = '''
app_id: test_app_id
''';
      final sankofaYaml = checkedYamlDecode(
        yaml,
        (m) => SankofaYaml.fromJson(m!),
      );
      expect(sankofaYaml.appId, 'test_app_id');
      expect(sankofaYaml.flavors, isNull);
      expect(sankofaYaml.baseUrl, isNull);
      expect(sankofaYaml.autoUpdate, isNull);
    });

    test('can be deserialized with auto-update', () {
      const yaml = '''
app_id: test_app_id
auto_update: true
''';
      final sankofaYaml = checkedYamlDecode(
        yaml,
        (m) => SankofaYaml.fromJson(m!),
      );
      expect(sankofaYaml.appId, 'test_app_id');
      expect(sankofaYaml.flavors, isNull);
      expect(sankofaYaml.baseUrl, isNull);
      expect(sankofaYaml.autoUpdate, isTrue);
    });

    test('can be deserialized without patch_verification', () {
      const yaml = '''
app_id: test_app_id
''';
      final sankofaYaml = checkedYamlDecode(
        yaml,
        (m) => SankofaYaml.fromJson(m!),
      );
      expect(sankofaYaml.appId, 'test_app_id');
      expect(sankofaYaml.patchVerification, isNull);
    });

    test('can be deserialized with patch_verification: strict', () {
      const yaml = '''
app_id: test_app_id
patch_verification: strict
''';
      final sankofaYaml = checkedYamlDecode(
        yaml,
        (m) => SankofaYaml.fromJson(m!),
      );
      expect(sankofaYaml.appId, 'test_app_id');
      expect(sankofaYaml.patchVerification, PatchVerification.strict);
    });

    test('can be deserialized with patch_verification: install_only', () {
      const yaml = '''
app_id: test_app_id
patch_verification: install_only
''';
      final sankofaYaml = checkedYamlDecode(
        yaml,
        (m) => SankofaYaml.fromJson(m!),
      );
      expect(sankofaYaml.appId, 'test_app_id');
      expect(sankofaYaml.patchVerification, PatchVerification.installOnly);
    });

    test('throws when patch_verification has invalid value', () {
      const yaml = '''
app_id: test_app_id
patch_verification: invalid_value
''';
      expect(
        () => checkedYamlDecode(yaml, (m) => SankofaYaml.fromJson(m!)),
        throwsA(
          isA<ParsedYamlException>().having(
            (e) => e.message,
            'message',
            contains('patch_verification'),
          ),
        ),
      );
    });

    group('AppIdExtension', () {
      test('getAppId returns base app id when no flavor is provided', () {
        const sankofaYaml = SankofaYaml(appId: 'test_app_id');
        expect(sankofaYaml.getAppId(), 'test_app_id');
      });

      test('getAppId returns base app id when flavor is not found', () {
        const sankofaYaml = SankofaYaml(
          appId: 'test_app_id',
          flavors: {
            'development': 'test_app_id1',
            'production': 'test_app_id2',
          },
        );
        expect(sankofaYaml.getAppId(flavor: 'staging'), 'test_app_id');
      });

      test('getAppId returns app id for flavor', () {
        const sankofaYaml = SankofaYaml(
          appId: 'test_app_id',
          flavors: {
            'development': 'test_app_id1',
            'production': 'test_app_id2',
          },
        );
        expect(sankofaYaml.getAppId(flavor: 'development'), 'test_app_id1');
        expect(sankofaYaml.getAppId(flavor: 'production'), 'test_app_id2');
      });
    });
  });
}
