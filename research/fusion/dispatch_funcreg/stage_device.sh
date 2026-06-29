#!/bin/bash
# Stage (or clear) the dispatch-funcreg patch into the app's on-device updater
# container, then (optionally) launch. iPhone is CoreDevice/network-only, so we
# push the updater dir via `xcrun devicectl device copy`.
#   ./stage_device.sh base    -> clear patch (next_boot=null) => boots BASE
#   ./stage_device.sh patch   -> stage patch #1 (Installed)   => boots PATCHED
#   ./stage_device.sh launch  -> just launch the app
set -e
DEV=72727D0B-1F51-56DF-BFA2-D320FA7477F8
BUNDLE=dev.sankofa.sankofaPushTest
HERE="$(cd "$(dirname "$0")" && pwd)"
PATCH_BC="$HERE/devicepatch/patch.bytecode"
WORK=/tmp/sankofa_dispatch_stage
MODE="${1:-patch}"

launch() {
  echo "### launch $BUNDLE ###"
  xcrun devicectl device process launch --terminate-existing \
    --device "$DEV" "$BUNDLE" 2>&1 | tail -3
}

if [ "$MODE" = "launch" ]; then launch; exit 0; fi

rm -rf "$WORK"; mkdir -p "$WORK/sankofa_updater/patches/1"
if [ "$MODE" = "base" ]; then
  printf '{"next_boot_patch":null,"last_booted_patch":null,"currently_booting_patch":null,"boot_started_at":null}' \
    > "$WORK/sankofa_updater/pointers.json"
  rmdir "$WORK/sankofa_updater/patches/1" "$WORK/sankofa_updater/patches" 2>/dev/null || true
else
  [ -f "$PATCH_BC" ] || { echo "missing $PATCH_BC (run build_patch.sh)"; exit 2; }
  SIZE=$(stat -f %z "$PATCH_BC")
  cp "$PATCH_BC" "$WORK/sankofa_updater/patches/1/dlc.vmcode"
  printf '{"kind":"Installed","signature":null,"size":%s}' "$SIZE" \
    > "$WORK/sankofa_updater/patches/1/state.json"
  printf '{"next_boot_patch":1,"last_booted_patch":null,"currently_booting_patch":null,"boot_started_at":null}' \
    > "$WORK/sankofa_updater/pointers.json"
  echo "staged patch #1 ($SIZE bytes)"
fi

echo "### push updater dir -> device app container (Documents/) ###"
xcrun devicectl device copy to --device "$DEV" \
  --domain-type appDataContainer --domain-identifier "$BUNDLE" \
  --source "$WORK/sankofa_updater" --destination "Documents/sankofa_updater" 2>&1 | tail -4
echo "### pushed ($MODE). Relaunch to apply. ###"
launch
