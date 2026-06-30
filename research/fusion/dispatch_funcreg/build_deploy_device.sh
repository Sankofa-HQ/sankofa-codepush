#!/bin/bash
# Build sankofa_push_test (dispatch-funcreg app) against the NEW iOS engine,
# swap the fresh Flutter.framework, re-sign, and install on the iPhone 14 Pro.
# The app's Panel/renderPanel/panelStatus get AOT-compiled with the new
# interleaved-dispatch / R8-loading convention (essential for the boot repoint).
set -e
NINJA=/Users/saytoonz/depot_tools/ninja
ENGSRC=/Users/saytoonz/Developer/Projects/Sankofa/flutter-deploy/sankofa-flutter/engine/src
SF=/Users/saytoonz/Developer/Projects/Sankofa/flutter-deploy/sankofa-flutter
APPDIR=/Users/saytoonz/Developer/Projects/Sankofa/flutter-deploy/sankofa_push_test
APP="$APPDIR/build/ios/iphoneos/Runner.app"
SC=/private/tmp/claude-501/-Users-saytoonz-Developer-Projects-Sankofa/f3bd1628-9053-45f8-8f29-c8899b0047e3/scratchpad
ID=A0C2EA3A622AB337AF2EA5387D3E15DA70B6D710
DEV=72727D0B-1F51-56DF-BFA2-D320FA7477F8   # Samuel's iPhone 14 Pro

echo "### 1. flutter build ios (vs new local engine) ###"
cd "$APPDIR"
"$SF/bin/flutter" clean >/dev/null 2>&1
"$SF/bin/flutter" build ios --release \
  --local-engine=ios_release --local-engine-host=mac_release_arm64 \
  --extra-front-end-options=--dynamic-interface="$APPDIR/sankofa_dynamic_interface.yaml" 2>&1 | tail -3

echo "### 2. swap fresh Flutter.framework + re-sign ###"
rsync -a --delete "$ENGSRC/out/ios_release/Flutter.framework/" "$APP/Frameworks/Flutter.framework/"
codesign --force --sign "$ID" --timestamp=none "$APP/Frameworks/Flutter.framework" 2>&1 | tail -1
codesign --force --sign "$ID" --entitlements "$SC/ent.plist" --timestamp=none "$APP" 2>&1 | tail -1
codesign --verify --deep --strict "$APP" && echo "resign OK"

echo "### 3. install on iPhone ###"
xcrun devicectl device install app --device "$DEV" "$APP" 2>&1 | tail -4
echo "### INSTALL DONE — launch BASE (no patch) first ###"
