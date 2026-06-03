# Sankofa CodePush — local engine development runbook

**Last updated:** 2026-06-02
**Proven on:** Apple Silicon M2, 8 GB RAM, macOS 15+, Xcode 16.x

This runbook captures the **end-to-end local setup** for developing Sankofa CodePush against our own Flutter engine fork — no Shorebird hosted dependencies. It's the working knowledge that took a full day to assemble.

---

## 1. Repository layout

| Repo | Path | Branch | What it is |
|---|---|---|---|
| `sankofa-codepush` | `flutter-deploy/sankofa-codepush` | `feat/cli-fully-sankofa` | The `sankofa` CLI (Dart) — release/patch/preview |
| `sankofa-flutter` | `flutter-deploy/sankofa-flutter` | `feat/own-engine-3.44` | Flutter SDK fork at upstream 3.44.0 + engine.version `6500c84e` |
| `sankofa-dart-sdk` | `flutter-deploy/sankofa-dart-sdk` | `feat/phase7-on-3.44-redo` | Dart SDK fork w/ `+sankofa-1` marker + dynamic-modules default + annotate-privates flag |
| `hello_codepush` | `flutter-deploy/hello_codepush` | (not git) | Test app for the CodePush flow |

The three forks aren't sub-modules of each other — they're independent repos that compose at build time via `DEPS`.

---

## 2. Prerequisites

### One-time tooling

```bash
# depot_tools (gclient + gn + ninja)
git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git ~/depot_tools
export PATH=$HOME/depot_tools:$PATH   # add to ~/.zshrc

# MetalToolchain (Xcode no longer bundles by default)
xcodebuild -downloadComponent MetalToolchain
```

### Disk space

The engine source + build outputs eat **~50 GB**:
- `engine/src/` after `gclient sync` = ~16 GB
- `out/ios_release/` after ninja = ~10 GB
- `out/mac_release_arm64/` after ninja = ~15 GB
- CIPD cache, prebuilt clangs, etc. = ~5 GB

### SSH access to private repos

`Sankofa-HQ/sankofa-dart-sdk` is private; SSH needed for push (HTTPS 408s on 1.3 GB packs).
```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_github -N ""
# Add ~/.ssh/id_ed25519_github.pub to https://github.com/settings/ssh/new
cat >> ~/.ssh/config <<'EOF'

Host github.com
  HostName github.com
  User git
  IdentityFile ~/.ssh/id_ed25519_github
  IdentitiesOnly yes
EOF
```

---

## 3. First-time engine setup

```bash
cd flutter-deploy/sankofa-flutter

# 3.1 Bootstrap gclient
cp engine/scripts/standard.gclient .gclient

# 3.2 URL rewrite so gclient pulls sankofa-dart-sdk from our LOCAL clone
# (avoids HTTPS 1.3 GB push limit on private repo; also faster)
git config --global url."file:///Users/$(whoami)/Developer/Projects/Sankofa/flutter-deploy/sankofa-dart-sdk".insteadOf "https://github.com/Sankofa-HQ/sankofa-dart-sdk.git"

# 3.3 gclient sync — pulls all deps including third_party + CIPD prebuilts
# ~30 GB download on first run, 30-60 min on residential network
export DEPOT_TOOLS_UPDATE=0
gclient sync --no-history --shallow

# 3.4 If gclient pulled wrong sub-dep revisions (Symptom: dart_style or
# native package compile errors), --force --reset:
gclient sync --no-history --shallow --force --reset
```

### Gotcha — bootstrap Dart SDK version

The dart-sdk's own DEPS pins a "bootstrap Dart" at `tools/sdks/dart-sdk/` via CIPD. Default value (`9ac06cdd18`) is Dart 3.10-dev — **too old to compile our 3.12 source**.

Our `sankofa-dart-sdk` fork on `feat/phase7-on-3.44-redo` includes commit `dd38f4ca5` that bumps `sdk_tag` to `98116461144` (Dart 3.12.0). If you get errors about "language version 3.12 is too high. Highest supported is 3.10" during build, this is your culprit. Verify:

```bash
engine/src/flutter/third_party/dart/tools/sdks/dart-sdk/bin/dart --version
# MUST show: Dart SDK version: 3.12.0 (stable)
```

If wrong, force-refresh:
```bash
rm -rf engine/src/flutter/third_party/dart/tools/sdks/dart-sdk
gclient sync --no-history --shallow
```

---

## 4. Build the engine (iOS device-arm64)

```bash
export PATH=$HOME/depot_tools:$PATH
cd engine/src

# 4.1 GN gen
./flutter/tools/gn \
  --ios --runtime-mode release \
  --no-prebuilt-dart-sdk \
  --gn-args=verify_sdk_hash=false

# 4.2 ninja
# CRITICAL: use -j 4 not -j 8 on 8 GB RAM. -j 8 triggers swap thrashing.
ninja -C out/ios_release -j 4

# 4.3 gen_snapshot is built as a side effect; verify:
file out/ios_release/artifacts_arm64/gen_snapshot_arm64
# expected: Mach-O 64-bit executable arm64
```

`--no-prebuilt-dart-sdk` is **mandatory** — without it, Flutter pulls a CIPD prebuilt Dart that silently ignores our `+sankofa-1` Dart-side source mods. `--gn-args=verify_sdk_hash=false` sets `sdk_hash = "0000000000"` so our patched snapshots accept any platform.dill.

### Verify the engine binary identity

```bash
strings out/ios_release/Flutter.framework/Flutter | grep -E "sankofa-1|3\.12\.0"
# Expected:
#   <commit-sha>+sankofa-1
#   3.12.0+sankofa-1 (stable) (...) on "ios_arm64"
```

If `+sankofa-1` is missing, you're linking against a stock prebuilt — `--no-prebuilt-dart-sdk` is the fix.

---

## 5. Build the host SDK (mac arm64)

Needed for `frontend_server_aot.dart.snapshot` (Dart→kernel compiler) and `dart2bytecode.dart.snapshot` (KBC bytecode emitter). These run on Mac during `flutter build ios`.

```bash
./flutter/tools/gn \
  --runtime-mode release \
  --mac --mac-cpu arm64 \
  --no-prebuilt-dart-sdk \
  --gn-args=verify_sdk_hash=false

ninja -C out/mac_release_arm64 -j 4
```

The host-SDK build has ~10,849 ninja steps. The **essential artifacts** for codepush are produced by step ~6000:
- `out/mac_release_arm64/dart-sdk/bin/snapshots/frontend_server_aot.dart.snapshot`
- `out/mac_release_arm64/dart-sdk/bin/snapshots/dart2bytecode.dart.snapshot`
- `out/mac_release_arm64/flutter_patched_sdk/platform_strong.dill`
- `out/mac_release_arm64/dart-sdk/bin/dart`

Once these exist on disk, **you can safely kill ninja** — the remaining steps are unittest binaries with LTO links that take 30-60 min each on 8 GB RAM. Not needed for the codepush flow.

### Gotcha — `analyze_snapshot` not built on Mac

Upstream Flutter only builds `analyze_snapshot` from Linux CI. Our fork's commit `0f4a58a6c` patches `engine/src/flutter/lib/snapshot/BUILD.gn` to enable it for `host_os == "mac"` too. After that patch:

```bash
ninja -C out/ios_release -j 4 flutter/lib/snapshot:generate_snapshot_bins
# Output: out/ios_release/clang_arm64/analyze_snapshot
```

---

## 6. Bootstrap the Sankofa CLI cache

The Sankofa CLI clones our `sankofa-flutter` to `bin/cache/flutter/<sha>/` and expects a populated artifact cache. For local dev, **symlink our build outputs into the expected paths**.

```bash
SF=/Users/$(whoami)/Developer/Projects/Sankofa/flutter-deploy/sankofa-flutter
SCP=/Users/$(whoami)/Developer/Projects/Sankofa/flutter-deploy/sankofa-codepush
SHA=$(cat "$SF/bin/internal/release-git-HEAD" 2>/dev/null || echo "dbdbed7892aac296d5fdc4dbb355247e314a663c")

# 6.1 Point CLI's flutter cache at our local checkout
mkdir -p "$SCP/bin/cache/flutter"
rm -rf "$SCP/bin/cache/flutter/$SHA"
ln -s "$SF" "$SCP/bin/cache/flutter/$SHA"

# 6.2 Point our flutter SDK's dart-sdk at our build output
cd "$SF/bin/cache"
rm -rf dart-sdk
ln -s "$SF/engine/src/out/mac_release_arm64/dart-sdk" dart-sdk

# 6.3 Stamps so Flutter's update_dart_sdk.sh skips re-downloading
echo -n "6500c84eba818b598fb967bd0276e6e50cdd02c9" > engine.stamp
echo -n "6500c84eba818b598fb967bd0276e6e50cdd02c9" > engine-dart-sdk.stamp
echo -n "6500c84eba818b598fb967bd0276e6e50cdd02c9" > engine_stamp.stamp
echo "1" > engine.realm

# 6.4 engine_stamp.json (minimal stub so flutter_tools doesn't 404)
cat > engine_stamp.json <<EOF
{
  "build_date": "2026-06-02T00:00:00.0Z",
  "git_revision": "6500c84eba818b598fb967bd0276e6e50cdd02c9",
  "git_revision_date": "2026-06-01T00:00:00.0Z",
  "content_hash": "c066c99c890ccaf8609d2726c7325d722066f1f9"
}
EOF

# 6.5 sky_engine + flutter_gpu packages
mkdir -p pkg
rm -rf pkg/sky_engine pkg/flutter_gpu
cp -r "$SF/engine/src/out/mac_release_arm64/gen/dart-pkg/sky_engine" pkg/
cp -r "$SF/engine/src/flutter/lib/gpu" pkg/flutter_gpu

# 6.6 flutter_patched_sdk + flutter_patched_sdk_product (link product to release)
mkdir -p artifacts/engine/common
rm -rf artifacts/engine/common/flutter_patched_sdk artifacts/engine/common/flutter_patched_sdk_product
ln -s "$SF/engine/src/out/mac_release_arm64/flutter_patched_sdk" artifacts/engine/common/flutter_patched_sdk
ln -s "$SF/engine/src/out/mac_release_arm64/flutter_patched_sdk" artifacts/engine/common/flutter_patched_sdk_product

# 6.7 ios-release artifacts (Flutter.xcframework, gen_snapshot_arm64, analyze_snapshot_arm64)
mkdir -p artifacts/engine/ios-release artifacts/engine/ios artifacts/engine/ios-profile

# Build the xcframework wrapper around our device-arm64 Flutter.framework
cd artifacts/engine/ios-release
rm -rf Flutter.xcframework
xcodebuild -create-xcframework \
  -framework "$SF/engine/src/out/ios_release/Flutter.framework" \
  -output Flutter.xcframework

ln -sf "$SF/engine/src/out/ios_release/artifacts_arm64/gen_snapshot_arm64" gen_snapshot_arm64
ln -sf "$SF/engine/src/out/ios_release/clang_arm64/analyze_snapshot" analyze_snapshot_arm64
echo "Sankofa local engine" > LICENSE

# 6.8 LICENSE files in ios/ios-profile (CLI checks they exist)
echo "Sankofa local engine" > "$SF/bin/cache/artifacts/engine/ios/LICENSE"
echo "Sankofa local engine" > "$SF/bin/cache/artifacts/engine/ios-profile/LICENSE"

# 6.9 darwin-x64 host tools (impellerc, dylibs, font-subset, const_finder, shader_lib)
DARWIN="$SF/bin/cache/artifacts/engine/darwin-x64"
SRC="$SF/engine/src/out/mac_release_arm64"
mkdir -p "$DARWIN"
echo "Sankofa local engine" > "$DARWIN/LICENSE"
ln -sf "$SRC/impellerc" "$DARWIN/impellerc"
ln -sf "$SRC/font-subset" "$DARWIN/font-subset"
ln -sf "$SRC/libtessellator.dylib" "$DARWIN/libtessellator.dylib"
ln -sf "$SRC/libpath_ops.dylib" "$DARWIN/libpath_ops.dylib"
ln -sf "$SRC/libimpeller.dylib" "$DARWIN/libimpeller.dylib"
ln -sf "$SRC/libEGL.dylib" "$DARWIN/libEGL.dylib"
ln -sf "$SRC/libGLESv2.dylib" "$DARWIN/libGLESv2.dylib"
ln -sf "$SRC/libvk_swiftshader.dylib" "$DARWIN/libvk_swiftshader.dylib"
ln -sf "$SRC/gen/const_finder.dart.snapshot" "$DARWIN/const_finder.dart.snapshot"
ln -sf "$SRC/shader_lib" "$DARWIN/shader_lib"

# 6.10 Write stamps for all cache artifacts so Flutter doesn't try to re-download
cd "$SF/bin/cache"
for name in flutter_sdk font-subset android-sdk windows-sdk linux-sdk macos-sdk ios-sdk ios-deploy ideviceinstaller libimobiledevice libimobiledeviceglue libplist libusbmuxd usbmuxd openssl; do
  echo -n "6500c84eba818b598fb967bd0276e6e50cdd02c9" > "$name.stamp"
done

# 6.11 Create flutter_release/<version> ref so the CLI finds our version
cd "$SF"
git tag flutter_release/3.44.0 dbdbed7892aac296d5fdc4dbb355247e314a663c 2>/dev/null
git update-ref refs/remotes/origin/flutter_release/3.44.0 dbdbed7892aac296d5fdc4dbb355247e314a663c
```

---

## 7. Push engine artifacts to the public CDN

After a fresh engine build, upload the artifacts to `download.sankofa.dev`
(B2 bucket `sankofa-public-engine` fronted by a Cloudflare Worker) so
customer builds can fetch them over HTTPS:

```bash
# Reads B2_ENGINE_KEY_ID + B2_ENGINE_APP_KEY from server/engine/.env.
sankofa-flutter/engine/scripts/upload-to-b2.sh
```

The script uploads ~95 MB (Android Maven JARs + POMs, iOS
Flutter.framework.zip + gen_snapshot_arm64). Run it once per engine
revision. URLs end up at e.g.
`https://download.sankofa.dev/download.flutter.io/io/flutter/.../*.{pom,jar}`.

If you ever update an artifact for the same engine.version (e.g. POM
metadata fix), purge Cloudflare cache too — the Worker has 24-hour
caching. Dashboard → Caching → Purge Everything is the blunt
instrument; per-URL purge is the precise one.

---

## 8. End-to-end release flow

```bash
cd flutter-deploy/hello_codepush

# Put our bundled flutter ahead in PATH (so "which flutter" finds ours)
export PATH=/Users/$(whoami)/Developer/Projects/Sankofa/flutter-deploy/sankofa-codepush/bin/cache/flutter/dbdbed7892aac296d5fdc4dbb355247e314a663c/bin:$HOME/depot_tools:$PATH

# Auth — load token from credentials.json (sankofa login already done)
export SANKOFA_TOKEN=$(python3 -c "import json; print(json.load(open('$HOME/Library/Application Support/sankofa/credentials.json'))['token'])")

# Release (Gradle fetches engine JARs from download.sankofa.dev automatically)
sankofa release ios --flutter-version=3.44.0
sankofa release android --flutter-version=3.44.0 --target-platform=android-arm64

# Preview (install + launch on connected device)
IOS_ID=$(xcrun xctrace list devices 2>&1 | grep "iPhone (" | head -1 | grep -oE "[A-F0-9-]+\)" | tr -d ')')
sankofa preview --platform=ios --release-version=<version> --device-id=$IOS_ID

ANDROID_ID=$(adb devices | awk 'NR>1 && $2=="device"{print $1; exit}')
sankofa preview --platform=android --release-version=<version> --device-id=$ANDROID_ID
```

---

## 9. What's broken / what's next

| Operation | State | Blocker |
|---|---|---|
| `sankofa release ios` | ✅ works | — |
| `sankofa preview` install+launch | ✅ works | — |
| `sankofa patch ios` | ❌ fails | Phase 1: `analyze_snapshot` needs codepush flags (`--compute_dd_table`, `--dd_slot_mapping`, etc.) added by the 12 engine-side patches |
| `sankofa release android` | ⏳ untested | Need to build Android engine slice: `./flutter/tools/gn --android --android-cpu=arm64 --runtime-mode release --no-prebuilt-dart-sdk` |

Phase 1 application plan: `engine/codepush-extraction/phase1-application-order.md` in `sankofa-flutter` repo. ~12-15 days of engine work to ship.

---

## 10. Useful debugging

```bash
# Check engine binary identity
strings build/ios/iphoneos/Runner.app/Frameworks/Flutter.framework/Flutter | grep sankofa

# What flutter is "which flutter" picking?
which flutter

# What dart is Flutter using?
$(which flutter | xargs dirname)/cache/dart-sdk/bin/dart --version

# Disk free during builds
df -h /
vm_stat | grep "Pages free"

# Inspect the CLI's sankofa.log
cat "$HOME/Library/Application Support/sankofa/logs/$(ls -t "$HOME/Library/Application Support/sankofa/logs/" | head -1)"

# Tail live builds
tail -f /tmp/ninja-ios.log
tail -f /tmp/sankofa-release-ios.log
```

---

## 11. Domains + infrastructure

- `api.sankofa.dev` — auth API (SANKOFA_TOKEN required). Customer's source of truth for releases + patches.
- `download.sankofa.dev` — public B2 bucket `sankofa-public-engine` fronted by a Cloudflare Worker (free tier — Workers > sankofa-engine-proxy). Origin: `s3.eu-central-003.backblazeb2.com`. CORS open. ~95 MB uploaded per engine.version via `sankofa-flutter/engine/scripts/upload-to-b2.sh`. See §7.
- `console.sankofa.dev` — customer-facing web console (auth + admin).

Never invent new domains. If you need an artifact URL the founder hasn't authorized, ask first.

---

## 12. Open-core monetization model (mirrors Shorebird)

**Public, anonymous-downloadable:** CLI, Flutter SDK fork, engine binaries, aot-tools.dill, patch binary. Apache 2.0; can't be closed anyway.

**Auth-gated (SANKOFA_TOKEN required):** Release creation, patch upload, device polling, multi-track distribution, analytics, console.

The MOAT is service quality + distribution scale, not tools. Don't try to lock down the tools — Shorebird tried, Flutter's `bin/cache` plumbing can't carry auth headers anyway.
