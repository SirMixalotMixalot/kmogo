#!/usr/bin/env bash
# Captures app footage for the Remotion launch video from the iOS simulator.
#   marketing/capture_assets.sh [simulator-udid]
# Writes screenshots, run clips (30 fps CFR) and share cards into
# marketing/launch-video/public/. Needs Xcode, ffmpeg and network (Apple Maps).
set -euo pipefail
cd "$(dirname "$0")/.."
SIM="${1:-$(xcrun simctl list devices booted -j | python3 -c 'import json,sys;print([d["udid"] for r in json.load(sys.stdin)["devices"].values() for d in r if d["state"]=="Booted"][0])')}"
PUB=marketing/launch-video/public
DD=marketing/build/DerivedData
RAW=marketing/build/raw
APP_ID=com.roamstudy.Roam
mkdir -p "$PUB/screens" "$PUB/clips" "$PUB/cards" "$RAW"

echo "Building Roam (Debug)…"
xcodebuild -project Roam.xcodeproj -scheme Roam -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath "$DD" build -quiet
APP="$DD/Build/Products/Debug-iphonesimulator/Roam.app"

xcrun simctl status_bar "$SIM" override --time "9:41" --batteryState charged --batteryLevel 100 \
  --wifiBars 3 --cellularMode active --cellularBars 4 --operatorName "" || true

fresh() { # fresh <settle-seconds> [launch args…]
  local settle=$1; shift
  xcrun simctl terminate "$SIM" $APP_ID 2>/dev/null || true
  xcrun simctl uninstall "$SIM" $APP_ID 2>/dev/null || true
  xcrun simctl install "$SIM" "$APP"
  xcrun simctl launch "$SIM" $APP_ID "$@" >/dev/null
  sleep "$settle"
}

shot() { # shot <name> <settle> [args…]
  local name=$1 settle=$2; shift 2
  fresh "$settle" "$@"
  xcrun simctl io "$SIM" screenshot --type=png "$PUB/screens/$name.png" >/dev/null 2>&1
  echo "  screen $name"
}

clip() { # clip <name> <settle> <seconds> [args…]
  local name=$1 settle=$2 secs=$3; shift 3
  fresh "$settle" "$@"
  rm -f "$RAW/$name.mp4"
  xcrun simctl io "$SIM" recordVideo --codec=h264 --force "$RAW/$name.mp4" >"$RAW/$name.log" 2>&1 &
  local pid=$!
  sleep 1
  if ! kill -0 $pid 2>/dev/null; then
    echo "recorder failed for $name:"; cat "$RAW/$name.log"
    echo "(if it says a recording is already in progress: xcrun simctl shutdown $SIM && xcrun simctl boot $SIM)"
    exit 1
  fi
  sleep "$((secs - 1))"
  kill -INT $pid
  wait $pid 2>/dev/null || true
  ffmpeg -v error -y -i "$RAW/$name.mp4" -vf "fps=30,scale=1080:-2:flags=lanczos" \
    -c:v libx264 -crf 17 -preset slow -pix_fmt yuv420p -an "$PUB/clips/$name.mp4"
  echo "  clip $name ($(ffprobe -v error -show_entries format=duration -of csv=p=0 "$PUB/clips/$name.mp4")s)"
}

TORONTO_RUN=(-demo -demoHome toronto -noSamples -warp 12 -marketing -demoExploreTo 43.6286,-79.4155)

echo "Recording run clips…"
clip run-ui    14 24 "${TORONTO_RUN[@]}"
clip run-clean 14 24 "${TORONTO_RUN[@]}" -cleanRun

echo "Capturing screens…"
shot onboarding 5
shot setup     18 -demo -exportCards
DOCS="$(xcrun simctl get_app_container "$SIM" $APP_ID data)/Documents"
cp "$DOCS"/card-*.png "$PUB/cards/" && echo "  share cards exported"
shot explore   16 -demo -demoHome toronto -noSamples -explore -exploreBearing 290
shot journey   16 -demo -tab 1
shot shop      16 -demo -tab 2
shot passport  16 -demo -tab 3
shot lobby     16 -demo -demoLobby

cp Roam/Assets.xcassets/AppIcon.appiconset/AppIcon.png "$PUB/icon.png"
xcrun simctl status_bar "$SIM" clear || true
echo "Done → $PUB"
