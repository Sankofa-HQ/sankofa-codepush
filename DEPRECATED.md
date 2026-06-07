# sankofa-codepush is DEPRECATED

**As of 2026-06-07, this repo is in maintenance-only mode.** Do not start new
work here. New customer integrations should use the unified Sankofa SDK +
β.3 KBC interpreter path (`sankofa_flutter.deploy`) instead.

## Why

`sankofa-codepush` is a fork of `shorebirdtech/{shorebird,updater}` (Apache 2.0)
that ports their AOT-based Flutter code-push approach onto Sankofa
infrastructure. It was the headline OTA product from 2026-05-27 to 2026-06-07.

It was superseded by **Sankofa CodePush β.3** — a KBC bytecode interpreter path
that:

- Works on iOS without the `Dart_LoadELF` kernel restriction this repo hit on
  iOS (see `~/.claude/projects/.../memory/project_ios_dlopen_elf_gap.md` for
  the full archaeology — App Store iOS forbids `PROT_EXEC` mmap of unsigned
  files, which kills the AOT-on-iOS path entirely)
- Works on Android with the same code path (cross-platform parity proven on
  Galaxy A14, 2026-06-07)
- Is App Store and Play Store compliant under Apple PLA § 3.3.2 + Google's
  Device and Network Abuse policy carve-outs for interpreted-code-in-a-VM
  (see the project's policy compliance memory for sources)
- Has a smaller customer integration footprint (one SDK, no separate updater
  Rust binary linked into the host app, no native plugin shim)

## What this repo still contains that's worth referencing

- **Engine integration glue** (`shell/common/sankofa/codepush.cc`,
  `snapshots_data_handle.cc`, etc.) — useful precedent for any future
  Path B (Shorebird linker+DD data-only patches) work, should that path
  ever become necessary
- **Rust updater** (`updater/library/`) — chain-safety + slot management
  patterns that informed the Dart-side `sankofa_flutter.deploy` implementation
- **Path B research** (`research/aot-tools-decompile/`) — reverse-engineering
  notes on Shorebird's aot-tools.dill, kept for future revisitation
- **`feat/cli-fully-sankofa` branch** — the last actively-developed branch,
  contains the Path B port progress + research material

## What's gone

- We are not shipping `sankofa_code_push` as the customer-facing Flutter OTA
  package. The unified `sankofa_flutter` is the canonical SDK.
- We are not maintaining the standalone Dart CLI in this repo
  (`packages/sankofa_cli/`). The TypeScript CLI at `cli/sankofa-cli/` (in
  the main Sankofa monorepo) is the canonical workstation tool.
- We are not adding new releases to npm / pub.dev from this repo.

## If you must use this repo

Pin to commit `62f87fc` (2026-06-07, the last commit before the deprecation
notice was added) and don't expect compatibility with future Sankofa
releases. File issues against the main Sankofa monorepo, not here.

## Canonical replacement docs

- [β.3 architecture](https://github.com/Sankofa-HQ/sankofa-flutter-deploy/blob/main/docs/codepush-beta3-architecture.md)
- [Integration cookbook](https://github.com/Sankofa-HQ/sankofa-flutter-deploy/blob/main/docs/codepush-integration-cookbook.md)
- [Flutter SDK upgrade playbook](https://github.com/Sankofa-HQ/sankofa-flutter-deploy/blob/main/docs/flutter-sdk-upgrade-playbook.md)
- [Engine build recipe](https://github.com/Sankofa-HQ/sankofa-flutter-deploy/blob/main/docs/engine-build-recipe.md)
- [Reference app: hello_codepush](https://github.com/Sankofa-HQ/sankofa-flutter-deploy/tree/main/hello_codepush)
