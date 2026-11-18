#!/bin/bash
# Archive Roam and upload it to App Store Connect (then it shows up in TestFlight).
#
#   scripts/release.sh            archive + upload
#   scripts/release.sh --no-upload  archive only (sanity check signing)
#
# Needs: Xcode signed in to the Apple ID on team X767SL92S7, and the app record
# for com.roamstudy.Roam created in App Store Connect before the first upload.
# The build number is the Unix time, so it is unique and increasing across every
# branch (commit counts collide between branches, and Apple rejects reused numbers).
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD=$(date +%s)
OUT=build/release
ARCHIVE="$OUT/Roam-$BUILD.xcarchive"
rm -rf "$ARCHIVE"
mkdir -p "$OUT"

echo "Archiving Roam build $BUILD…"
xcodebuild archive \
  -project Roam.xcodeproj -scheme Roam -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$BUILD" \
  > "$OUT/archive.log" 2>&1 || {
    tail -40 "$OUT/archive.log" >&2
    echo "Archive failed; full log: $OUT/archive.log" >&2
    exit 1
  }
echo "Archive: $ARCHIVE"

if [ "${1:-}" = "--no-upload" ]; then
  exit 0
fi

echo "Uploading to App Store Connect…"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist Config/ExportOptions.plist \
  -exportPath "$OUT/export-$BUILD" \
  -allowProvisioningUpdates
echo "Uploaded build $BUILD. It appears in TestFlight after processing (usually 5–15 min)."
