// cspell:words plist plists

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sankofa_cli/src/config/sankofa_yaml.dart';
import 'package:sankofa_cli/src/sankofa_env.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:xml/xml.dart';

/// A reference to a [NativeConfigEditor] instance.
final nativeConfigEditorRef = create(NativeConfigEditor.new);

/// The [NativeConfigEditor] instance available in the current zone.
NativeConfigEditor get nativeConfigEditor => read(nativeConfigEditorRef);

/// Identifies a Sankofa CodePush field that exists in both the host app's
/// `sankofa.yaml` source-of-truth file and one of the platform-native config
/// files.
class _ConfigKey {
  const _ConfigKey({
    required this.android,
    required this.ios,
    required this.value,
  });

  /// Manifest meta-data `android:name` key.
  final String android;

  /// Info.plist top-level key.
  final String ios;

  /// The value read from `sankofa.yaml`.
  final String value;
}

/// Edits the host app's platform-native config files (AndroidManifest.xml and
/// ios/Runner/Info.plist) to carry the same Sankofa CodePush settings the
/// engine reads at startup.
///
/// The Sankofa Flutter engine (Phase 0.75+) prefers native platform config
/// over the legacy `sankofa.yaml` flutter asset; this editor exists so the
/// CLI can keep the native config in sync with `sankofa.yaml` (which stays
/// as the customer-edited source of truth) on every `sankofa release` /
/// `sankofa patch`.
///
/// All sync methods are idempotent — running them twice does the same thing
/// once.
class NativeConfigEditor {
  /// Inserts or updates `dev.sankofa.code_push.*` meta-data entries inside the
  /// host app's `android/app/src/main/AndroidManifest.xml` `<application>`
  /// element, sourcing values from [config].
  ///
  /// Returns the list of `android:name` keys that were added or updated. An
  /// empty list means no edits were needed (file already in sync) or the
  /// manifest could not be located.
  ///
  /// Preserves existing file formatting via targeted regex edits; falls back
  /// to inserting new entries just before `</application>`.
  List<String> syncAndroidManifestMetadata({required SankofaYaml config}) {
    final manifestFile = _androidManifestFile;
    if (manifestFile == null || !manifestFile.existsSync()) return const [];

    final keys = _keysFromConfig(config);
    if (keys.isEmpty) return const [];

    final contents = manifestFile.readAsStringSync();

    // Determine what's missing/outdated by parsing the XML once.
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(contents);
    } on XmlException {
      return const [];
    }
    final appElement = doc.rootElement.findElements('application').firstOrNull;
    if (appElement == null) return const [];

    final existingValues = <String, String?>{};
    for (final element in appElement.findElements('meta-data')) {
      final name = element.getAttribute('android:name');
      if (name != null) {
        existingValues[name] = element.getAttribute('android:value');
      }
    }

    final changed = <String>[];
    var updated = contents;
    final indent = _detectIndent(contents);

    for (final key in keys) {
      if (existingValues[key.android] == key.value) continue;
      changed.add(key.android);

      final nameEscaped = RegExp.escape(key.android);
      // Match a meta-data tag for this name in either single-line or
      // multi-line shape. Captures android:value for replacement.
      final existingRegex = RegExp(
        '<meta-data\\b[^>]*?android:name="$nameEscaped"[^>]*?/>',
        dotAll: true,
      );

      final replacement =
          '<meta-data\n'
          '$indent    android:name="${key.android}"\n'
          '$indent    android:value="${_xmlAttrEscape(key.value)}" />';

      if (existingRegex.hasMatch(updated)) {
        updated = updated.replaceFirst(existingRegex, replacement);
      } else {
        // Insert just before the closing </application> tag, preserving the
        // existing indent level of meta-data siblings.
        final closeRegex = RegExp(r'(\s*)</application>');
        final match = closeRegex.firstMatch(updated);
        if (match == null) continue;
        final insertionIndent = indent;
        updated = updated.replaceRange(
          match.start,
          match.start,
          '\n$insertionIndent$replacement',
        );
      }
    }

    if (changed.isEmpty) return const [];
    manifestFile.writeAsStringSync(updated);
    return changed;
  }

  /// Inserts or updates `SankofaCodePush*` keys inside the host app's
  /// `ios/Runner/Info.plist`, sourcing values from [config].
  ///
  /// Returns the list of plist keys that were added or updated.
  ///
  /// Preserves existing file formatting via targeted regex edits over the
  /// XML plist source (does NOT round-trip through `propertylistserialization`,
  /// which would rewrite Xcode's whitespace).
  List<String> syncIosInfoPlist({required SankofaYaml config}) {
    final plistFile = _iosInfoPlistFile;
    if (plistFile == null || !plistFile.existsSync()) return const [];

    final keys = _keysFromConfig(config);
    if (keys.isEmpty) return const [];

    final contents = plistFile.readAsStringSync();
    final changed = <String>[];
    var updated = contents;
    final indent = _detectPlistIndent(contents);

    for (final key in keys) {
      final keyEscaped = RegExp.escape(key.ios);
      // Match <key>X</key>\s*<string>OLD</string> and replace OLD.
      final existingRegex = RegExp(
        '(<key>$keyEscaped</key>\\s*<string>)([^<]*)(</string>)',
        dotAll: true,
      );
      final match = existingRegex.firstMatch(updated);
      if (match != null) {
        final currentValue = match.group(2);
        if (currentValue == key.value) continue; // already in sync
        changed.add(key.ios);
        updated = updated.replaceRange(
          match.start,
          match.end,
          '${match.group(1)}${_xmlTextEscape(key.value)}${match.group(3)}',
        );
      } else {
        // Insert before the final </dict> (which precedes </plist>).
        final closeRegex = RegExp(r'(\s*)</dict>\s*</plist>');
        final closeMatch = closeRegex.firstMatch(updated);
        if (closeMatch == null) continue;
        changed.add(key.ios);
        final block =
            '$indent<key>${key.ios}</key>\n'
            '$indent<string>${_xmlTextEscape(key.value)}</string>\n';
        updated = updated.replaceRange(
          closeMatch.start,
          closeMatch.start,
          '\n$block',
        );
      }
    }

    if (changed.isEmpty) return const [];
    plistFile.writeAsStringSync(updated);
    return changed;
  }

  /// One-shot migration that removes the legacy `sankofa.yaml` flutter
  /// asset entry from `pubspec.yaml` and deletes the file from the project
  /// root. Run after the native-config sync has succeeded so customers don't
  /// lose config mid-migration.
  ///
  /// Returns true if anything was removed. Idempotent — running twice is a
  /// no-op.
  ///
  /// Does NOT delete the customer's source-of-truth `sankofa.yaml`; the
  /// CLI still reads it. Only removes the bundled-as-asset entry from
  /// pubspec, since the engine now reads from native platform config.
  bool removeLegacyYamlAssetEntry() {
    final root = sankofaEnv.getFlutterProjectRoot();
    if (root == null) return false;
    final pubspecFile = sankofaEnv.getPubspecYamlFile(cwd: root);
    if (!pubspecFile.existsSync()) return false;

    final contents = pubspecFile.readAsStringSync();
    // Match `  - sankofa.yaml` or `    - sankofa.yaml` etc, with the line
    // terminator. Conservative: only remove lines that match exactly to
    // avoid touching unrelated entries.
    final entryRegex = RegExp(
      r'^[ \t]+- sankofa\.yaml[ \t]*(\r?\n)',
      multiLine: true,
    );
    if (!entryRegex.hasMatch(contents)) return false;
    final updated = contents.replaceAll(entryRegex, '');
    if (updated == contents) return false;
    pubspecFile.writeAsStringSync(updated);
    return true;
  }

  // ---------------------------------------------------------------------

  File? get _androidManifestFile {
    final root = sankofaEnv.getFlutterProjectRoot();
    if (root == null) return null;
    return File(
      p.join(
        root.path,
        'android',
        'app',
        'src',
        'main',
        'AndroidManifest.xml',
      ),
    );
  }

  File? get _iosInfoPlistFile {
    final root = sankofaEnv.getFlutterProjectRoot();
    if (root == null) return null;
    return File(p.join(root.path, 'ios', 'Runner', 'Info.plist'));
  }

  List<_ConfigKey> _keysFromConfig(SankofaYaml config) {
    final keys = <_ConfigKey>[
      _ConfigKey(
        android: 'dev.sankofa.code_push.app_id',
        ios: 'SankofaCodePushAppId',
        value: config.appId,
      ),
    ];
    final baseUrl = config.baseUrl;
    if (baseUrl != null) {
      keys.add(
        _ConfigKey(
          android: 'dev.sankofa.code_push.base_url',
          ios: 'SankofaCodePushBaseURL',
          value: baseUrl,
        ),
      );
    }
    return keys;
  }

  /// Detects the indent (single level) used inside `<application>` by reading
  /// the leading whitespace of the first child element. Falls back to four
  /// spaces.
  String _detectIndent(String manifestContents) {
    final match = RegExp(
      r'<application\b[^>]*>\s*\n([ \t]+)\S',
      dotAll: true,
    ).firstMatch(manifestContents);
    return match?.group(1) ?? '        ';
  }

  /// Detects the indent used inside the top-level plist `<dict>` by reading
  /// the leading whitespace of the first `<key>` element. Falls back to a tab.
  String _detectPlistIndent(String plistContents) {
    final match = RegExp(r'<dict>\s*\n([ \t]+)<key>').firstMatch(plistContents);
    return match?.group(1) ?? '\t';
  }

  /// Minimal XML attribute escape — quotes + ampersands. Sankofa CodePush
  /// values are app ids and URLs in practice, so this covers the realistic
  /// surface.
  String _xmlAttrEscape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll('<', '&lt;');

  /// Minimal XML text escape (used inside `<string>` plist elements).
  String _xmlTextEscape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}
