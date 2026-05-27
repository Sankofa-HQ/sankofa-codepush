/// Sankofa Web Console URLs.
class SankofaWebConsole {
  /// Returns a [Uri] for the Sankofa Web Console.
  static Uri uri(String path) {
    return Uri.parse('https://console.sankofa.dev/$path');
  }

  /// Returns a [Uri] for the Sankofa Web Console login page.
  static Uri appReleaseUri(String appId, int releaseId) {
    return SankofaWebConsole.uri('apps/$appId/releases/$releaseId');
  }
}
