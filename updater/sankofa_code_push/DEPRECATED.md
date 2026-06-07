# sankofa_code_push (Dart package) is DEPRECATED

**As of 2026-06-07, this Dart package is deprecated.** Do not depend on it
for new integrations.

## What replaced it

Sankofa's canonical Flutter OTA SDK is **`sankofa_flutter`** (the unified
SDK). Use:

```yaml
dependencies:
  sankofa_flutter: ^1.0.0           # or path: ../sdks/sankofa_sdk_flutter
  dynamic_modules:
    path: ../sankofa-dart-sdk/pkg/dynamic_modules
```

```dart
import 'package:dynamic_modules/dynamic_modules.dart';
import 'package:sankofa_flutter/sankofa_flutter.dart';

await Sankofa.instance.init(
  apiKey: '<sk_live_*>',
  endpoint: 'https://api.sankofa.dev',
  enableDeploy: true,
  deployOptions: SankofaDeployOptions(signingPubkeyB64: '<pubkey>'),
);
final staged = await Sankofa.instance.deploy?.tryApplyStagedKbcPatch(
  loader: loadModuleFromBytes,
);
```

`Sankofa.instance.deploy` has the methods this package's `SankofaUpdater`
exposed (`checkForUpdate`, etc.) plus the β.3 KBC interpreter pipeline this
package never had.

## Why deprecated

This package is a Dart-level clone of Shorebird's `shorebird_code_push`
package — same `SankofaUpdater` class, same `Patch`/`UpdateStatus` types,
same API shape. It was the customer-facing Dart surface for the AOT/Rust-
updater path inherited from the Shorebird fork.

That path is dead on iOS (App Store kernel forbids `PROT_EXEC` mmap of
unsigned files — see `project_ios_dlopen_elf_gap` memory). On Android the
β.3 KBC interpreter (`sankofa_flutter.deploy`) now covers the same use case
with cross-platform parity (proven 2026-06-07).

Maintaining two Flutter OTA SDKs (this + `sankofa_flutter`) isn't worth the
fork-tax. Use `sankofa_flutter`.

## See

- [β.3 architecture](https://github.com/Sankofa-HQ/sankofa-flutter-deploy/blob/main/docs/codepush-beta3-architecture.md)
- [Integration cookbook](https://github.com/Sankofa-HQ/sankofa-flutter-deploy/blob/main/docs/codepush-integration-cookbook.md)
