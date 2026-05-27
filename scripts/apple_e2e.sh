#!/bin/bash -e -x

# Validates that iOS release and patch commands work as expected.
# This needs to be run locally on a machine with an iOS device attached.

rm -rf sankofa_temp
flutter create sankofa_temp --empty --platforms ios,macos
cd sankofa_temp
sankofa init -f
CI=1 sankofa release --platforms ios,macos
sed -i .orig 's/Hello World/Hello Sankofa/g' lib/main.dart
CI=1 sankofa patch --platforms ios,macos --release-version latest

sankofa preview --release-version 0.1.0+0.1.0 --platform ios > /dev/null &
sankofa preview --release-version 0.1.0+0.1.0 --platform macos > /dev/null &

echo "Once the patch is installed, kill the app and verify the 'Hello world! has been replaced by 'Hello sankofa'"