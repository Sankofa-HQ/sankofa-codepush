import 'package:scoped_deps/scoped_deps.dart';
import 'package:sankofa_cli/src/sankofa_env.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// A reference to a [PubspecEditor] instance.
final pubspecEditorRef = create(PubspecEditor.new);

/// The [PubspecEditor] instance available in the current zone.
PubspecEditor get pubspecEditor => read(pubspecEditorRef);

/// {@template pubspec_editor}
/// A class that exposes APIs to edit the current project's `pubspec.yaml`.
/// {@endtemplate}
class PubspecEditor {
  /// Adds sankofa.yaml to the assets section of the pubspec.yaml file.
  /// Does nothing if the pubspec.yaml file already contains sankofa.yaml.
  /// Does nothing if a flutter project root cannot be found.
  void addSankofaYamlToPubspecAssets() {
    if (sankofaEnv.pubspecContainsSankofaYaml) return;
    _ensureAsset('sankofa.yaml');
  }

  /// Ensures the engine code-push config asset (`sankofa.yaml`) is listed
  /// in the pubspec assets so it gets bundled into the app.
  ///
  /// `sankofa.yaml` is the single source of truth the customer edits; our
  /// Sankofa-built Flutter engine reads it at startup. Idempotent.
  void ensureEngineConfigYamlAsset() {
    _ensureAsset('sankofa.yaml');
  }

  /// Adds [asset] to `flutter.assets` in pubspec.yaml if not already present.
  /// Does nothing if a flutter project root cannot be found.
  void _ensureAsset(String asset) {
    final root = sankofaEnv.getFlutterProjectRoot();
    // TODO(felangel): this should throw an exception instead of returning
    // to make it explicit that the edit operation failed.
    if (root == null) return;

    final pubspecFile = sankofaEnv.getPubspecYamlFile(cwd: root);
    final pubspecContents = pubspecFile.readAsStringSync();
    final editor = YamlEditor(pubspecContents);
    final yaml = loadYaml(pubspecContents, sourceUrl: pubspecFile.uri) as Map;

    if (!yaml.containsKey('flutter') || yaml['flutter'] == null) {
      editor.update(
        ['flutter'],
        {
          'assets': [asset],
        },
      );
    } else {
      if (!(yaml['flutter'] as Map).containsKey('assets')) {
        editor.update(['flutter', 'assets'], [asset]);
      } else {
        final assets = (yaml['flutter'] as Map)['assets'] as List;
        if (!assets.contains(asset)) {
          editor.update(['flutter', 'assets'], [...assets, asset]);
        }
      }
    }

    if (editor.edits.isEmpty) return;

    pubspecFile.writeAsStringSync(editor.toString());
  }
}
