import 'package:sankofa_cli/src/sankofa_web_console.dart';
import 'package:test/test.dart';

void main() {
  group(SankofaWebConsole, () {
    test('uri returns the correct uri with the received path', () {
      expect(
        SankofaWebConsole.uri('path'),
        Uri.parse('https://console.sankofa.dev/path'),
      );
    });

    test('appReleaseUri returns the correct uri to an app release', () {
      expect(
        SankofaWebConsole.appReleaseUri('appId', 123),
        Uri.parse('https://console.sankofa.dev/apps/appId/releases/123'),
      );
    });
  });
}
