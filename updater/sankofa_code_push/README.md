
<div align=center>
 <img src= "https://raw.githubusercontent.com/sankofatech/brand/904722544742c13348f1854a5cc45f4ed223cd17/logo-wordmark/logo_wordmark.png" alt="Sankofa logo">
<h1>Code Push </h1>

[![Discord](https://img.shields.io/discord/1030243211995791380?style=for-the-badge&logo=discord&color=blue)](https://discord.gg/sankofa)

[![ci](https://github.com/sankofatech/updater/actions/workflows/main.yaml/badge.svg)](https://github.com/sankofatech/updater/actions/workflows/main.yaml)
[![codecov](https://codecov.io/gh/sankofatech/updater/branch/main/graph/badge.svg)](https://codecov.io/gh/sankofatech/updater)
[![License: MIT][license_badge]][license_link]

<p align=center> Instantly push updates to your Flutter app without lengthy app store review cycles. </p>

[Website](https://sankofa.dev?utm_source=pubdev) • [Docs](https://docs.sankofa.dev?utm_source=pubdev) • [X](https://x.com/sankofadev)• [YouTube](https://www.youtube.com/@sankofa) 
 </div>

This Dart package communicates with the [Sankofa](https://sankofa.dev) Code Push Updater to:

- ✅ Get the currently installed patch version
- ✅ Check whether a new patch is available
- ✅ Download new patches

## Demo 
Explore this [interactive demo](https://docs.sankofa.dev/code-push/?utm_source=pubdev) to learn more

## Getting Started

If your Flutter app does not already use Sankofa, follow our
[Getting Started Guide]([https://docs.sankofa.dev/getting-started/?utm_source=pubdev]) to add code push to your
app.

## Installation

```sh
flutter pub add sankofa_code_push
```

## Usage

Sankofa automatically checks for and downloads updates in the background.
Most apps do not need this package. This package is for apps that want
additional control, such as displaying update status to the user or prompting
before downloading.

**Important:** `checkForUpdate()` and `update()` make network calls that may
be slow. Avoid gating app startup on the result (e.g. awaiting in `initState`),
as the app may appear stuck on the splash screen. Use `.then()` instead.

```dart
import 'package:sankofa_code_push/sankofa_code_push.dart';

void main() => runApp(const MyApp());

// [Other code here]

class _MyHomePageState extends State<MyHomePage> {
  final updater = SankofaUpdater();
  Patch? _currentPatch;
  bool _updateAvailable = false;

  @override
  void initState() {
    super.initState();

    // Read the current patch number (null if no patch is installed).
    updater.readCurrentPatch().then((patch) {
      setState(() => _currentPatch = patch);
    });

    // Check if an update is available to show in the UI.
    updater.checkForUpdate().then((status) {
      setState(() => _updateAvailable = status == UpdateStatus.outdated);
    });
  }

  // [Other code here]
}
```

See the example for a complete working app.

### Tracks

Sankofa supports publishing patches to different tracks, which can be
used to target different segments of your user base. See the [percentage based rollout 
guide](https://docs.sankofa.dev/code-push/guides/percentage-based-rollouts/) for implementation details.

You must first publish a patch to a specific track (patches are published to the
`stable` track by default). To publish a patch to a different track, update your
patch command to use the `--track` argument:

```sh
sankofa patch android --track beta
```

(We're just using Android for this example. Tracks are supported on all
platforms).

To check for updates on a given track, pass an `UpdateTrack` to
`checkForUpdate` (and `update` if you use it):

```dart
updater.checkForUpdate(track: UpdateTrack.beta);
```

You can also use custom track names. When creating a patch, specify a track name
like this:

```sh
sankofa patch android --track my-custom-track
```

And:

```dart
updater.checkForUpdate(track: UpdateTrack('my-custom-track'));
```

**Note:** Updating to a specific track does not uninstall patches from other
tracks. See [#3484](https://github.com/sankofatech/sankofa/issues/3484)
for details.

## Join us on Discord!

We have an active [Discord server](https://discord.gg/sankofa) where you can
ask questions and get help.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

[license_badge]: https://img.shields.io/badge/license-MIT-blue.svg
[license_link]: https://opensource.org/licenses/MIT
