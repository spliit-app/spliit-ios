#!/usr/bin/env bash
#
# Produces the App Store screenshots, one set per language and per device size.
#
#   Scripts/screenshots.sh                          # everything the listing needs
#   Scripts/screenshots.sh --languages en           # just English
#   Scripts/screenshots.sh --devices iphone-6.9     # just the iPhone set
#
# It drives `SpliitUITests/ScreenshotTests` — the only suite `make e2e` skips — against the
# shared instance from `make e2e-up`, once per language, with `-testLanguage` so the app and its
# seeded data are both in that language. The pictures come out of the result bundle and land in
# Docs/app-store/screenshots/<locale>/<device>/, numbered in the order App Store Connect should
# show them.
#
# Before each run the simulator is set to that language, booted, pinned to light appearance and
# given a 9:41 status bar, so two runs a week apart differ only where the app differs.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

LANGUAGES=(en fr)
DEVICES=(iphone-6.9 ipad-13)
OUTPUT="Docs/app-store/screenshots"
PROJECT="Spliit.xcodeproj"
SCHEME="Spliit"
DERIVED="build"
# A name of its own, and one per worktree: `make e2e` in another worktree must not find itself
# sharing a device with a run that is busy pinning its clock to 9:41.
SIM_PREFIX="Spliit Shots $(basename "$PWD")"

# What App Store Connect asks for. The 6.9" iPhone and the 13" iPad are the two sizes a
# universal app must supply; every smaller size is derived from them by Apple.
device_type() {
  case "$1" in
    iphone-6.9) echo "iPhone 17 Pro Max" ;;
    ipad-13)    echo "iPad Pro 13-inch (M5)" ;;
    *) echo "unknown device profile: $1" >&2; return 1 ;;
  esac
}

device_size() {
  case "$1" in
    iphone-6.9) echo "1320x2868" ;;
    ipad-13)    echo "2064x2752" ;;
  esac
}

# The App Store locale each language is published under, and the region that decides how dates
# and money are written inside the screenshots.
locale_for() {
  case "$1" in
    en) echo "en-US" ;;
    fr) echo "fr-FR" ;;
    *)  echo "$1" ;;
  esac
}

region_for() {
  case "$1" in
    en) echo "US" ;;
    fr) echo "FR" ;;
    *)  echo "US" ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --languages) IFS=' ' read -r -a LANGUAGES <<< "$2"; shift 2 ;;
    --devices)   IFS=' ' read -r -a DEVICES <<< "$2"; shift 2 ;;
    --output)    OUTPUT="$2"; shift 2 ;;
    -h|--help)   sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

echo "==> Spliit instance"
make e2e-up

for device in "${DEVICES[@]}"; do
  type_name="$(device_type "$device")"
  sim_name="$SIM_PREFIX $device"

  echo "==> $type_name"
  if ! xcrun simctl list devices | grep -qF "    $sim_name ("; then
    xcrun simctl create "$sim_name" "$type_name" > /dev/null
  fi
  udid="$(xcrun simctl list devices -j | python3 Scripts/find-simulator.py "$sim_name")"

  for language in "${LANGUAGES[@]}"; do
    locale="$(locale_for "$language")"
    region="$(region_for "$language")"
    bundle="$DERIVED/screenshots-$device-$language.xcresult"
    destination="$OUTPUT/$locale/$device"

    echo "==> $locale on $device"

    # The *device's* language, not only the app's. `-testLanguage` covers everything the app
    # draws, but the status bar is drawn by the system — and on iPad it carries the date, which
    # came out as "Lundi 24 août" over the English screenshots. Written while the device is shut
    # down, because the preference is read at boot.
    #
    # `plutil` rather than `defaults`: `defaults` goes through cfprefsd, which caches the file
    # and writes it back when it feels like it. CoreSimulator writes the same file when it
    # creates and boots a device, and between the two the language quietly failed to take —
    # reliably so on the second device of a run, which is how English screenshots ended up with
    # a French status bar. `plutil` edits the file on disk and nothing else touches it while the
    # device is off.
    plist="$HOME/Library/Developer/CoreSimulator/Devices/$udid/data/Library/Preferences/.GlobalPreferences.plist"
    xcrun simctl shutdown "$udid" 2>/dev/null || true
    plutil -replace AppleLanguages -json "[\"$language\"]" "$plist"
    plutil -replace AppleLocale -string "${language}_${region}" "$plist"

    xcrun simctl boot "$udid" 2>/dev/null || true
    xcrun simctl bootstatus "$udid" -b > /dev/null

    # And check that it took, because the way this fails is a screenshot that looks right until
    # someone reads the status bar. A wrong language here is worth a stopped run.
    actual="$(xcrun simctl spawn "$udid" defaults read -g AppleLanguages | tr -d ' \n()\"')"
    if [[ "$actual" != "$language"* ]]; then
      echo "the simulator came up in '$actual', not '$language'" >&2
      exit 1
    fi

    # Everything else that would otherwise date the picture: the clock, the battery, the signal,
    # and whether the machine happened to be in dark mode that evening.
    xcrun simctl ui "$udid" appearance light > /dev/null

    # The keyboard's "slide to type" introduction is not suppressed here. It looks like a
    # preference — `DidShowContinuousPathIntroduction` — but that one belongs to Settings, and
    # writing it changes nothing: the splash still comes up the first time a keyboard does, on
    # every fresh device, and this run makes a fresh device every time. `ScreenshotTests`
    # dismisses it instead, which is the only thing that actually works.
    xcrun simctl status_bar "$udid" override \
      --time "9:41" \
      --dataNetwork wifi --wifiMode active --wifiBars 3 \
      --cellularMode active --cellularBars 4 --operatorName "" \
      --batteryState charged --batteryLevel 100

    rm -rf "$bundle"

    # Serial, not parallel: parallel testing clones the simulator, and a clone is not the device
    # the status bar was pinned on. `-testLanguage` reaches the app under test and the runner
    # alike, which is what makes the seeded data French as well as the interface.
    xcodebuild test \
      -project "$PROJECT" -scheme "$SCHEME" \
      -destination "platform=iOS Simulator,id=$udid" \
      -derivedDataPath "$DERIVED" \
      -only-testing:SpliitUITests/ScreenshotTests \
      -testLanguage "$language" -testRegion "$region" \
      -parallel-testing-enabled NO \
      -resultBundlePath "$bundle" \
      CODE_SIGNING_ALLOWED=NO \
      -quiet

    rm -rf "$destination" "$DERIVED/attachments-$device-$language"
    mkdir -p "$destination"
    xcrun xcresulttool export attachments \
      --path "$bundle" \
      --output-path "$DERIVED/attachments-$device-$language" > /dev/null

    # The export names files after the attachment's UUID and records the name the test gave it
    # in a manifest. The name is the whole point — it is what orders the set in App Store
    # Connect — so the manifest is what decides the file names here.
    python3 Scripts/name-screenshots.py \
      "$DERIVED/attachments-$device-$language" "$destination" "$(device_size "$device")"

    xcrun simctl status_bar "$udid" clear
  done

  # Left behind only by a run that failed, where having the device to look at is the point.
  xcrun simctl shutdown "$udid" 2>/dev/null || true
  xcrun simctl delete "$udid"
done

echo
echo "Screenshots in $OUTPUT:"
find "$OUTPUT" -name '*.png' | sort
