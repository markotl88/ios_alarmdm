#!/bin/bash
# Captures App Store screenshots at native resolution for both required sets.
#
# App Store Connect requires one set per device class the app supports:
#   iPhone 6.9"  1320x2868
#   iPad   13"   2064x2752   (also accepts 2048x2732 from the 12.9" simulator)
#
# It scales those down for every smaller device itself, so these two are enough.
#
#   ./tools/screenshots.sh            both device classes
#   ./tools/screenshots.sh iphone     just the phone
#   ./tools/screenshots.sh ipad       just the tablet

set -e
OUT="${OUT:-$HOME/Desktop/AlarmDM-screenshots}"
WANT="${1:-all}"

SHOTS=(
  "01-radio:Radio tab, kartica sa kasetofonom"
  "02-emisije:Tab Emisije, lista"
  "03-player:Full screen player, epizoda u toku"
  "04-epizode:Lista epizoda jedne emisije, sa filterima"
  "05-podrzi:Tab Podrži"
)

# Picks the first available simulator whose name matches, so this keeps working
# when Xcode renames or retires a device.
resolve_device() {
  xcrun simctl list devices available \
    | grep -oE "^ +$1[^(]*" \
    | sed 's/^ *//; s/ *$//' \
    | head -1
}

capture_set() {
  local device="$1" expect_w="$2" expect_h="$3" folder="$4"

  if [ -z "$device" ]; then
    echo "⚠ nema dostupnog simulatora za $folder — preskačem"
    echo "  instaliraj ga: Xcode → Settings → Components"
    return
  fi

  mkdir -p "$OUT/$folder"
  echo
  echo "════ $folder — $device ($expect_w×$expect_h) ════"
  xcrun simctl boot "$device" 2>/dev/null || true
  open -a Simulator
  sleep 4

  for entry in "${SHOTS[@]}"; do
    local name="${entry%%:*}" desc="${entry#*:}"
    printf "→ %s\n  postavi ekran: %s\n  Return za snimanje, s za preskakanje: " "$name" "$desc"
    read -r answer
    [ "$answer" = "s" ] && { echo "  preskočeno"; continue; }

    xcrun simctl io booted screenshot "$OUT/$folder/$name.png" >/dev/null 2>&1
    local w h
    w=$(sips -g pixelWidth "$OUT/$folder/$name.png" | awk '/pixelWidth/{print $2}')
    h=$(sips -g pixelHeight "$OUT/$folder/$name.png" | awk '/pixelHeight/{print $2}')
    if [ "$w" = "$expect_w" ] && [ "$h" = "$expect_h" ]; then
      echo "  ✓ $w×$h"
    else
      echo "  ⚠ $w×$h — očekivano $expect_w×$expect_h; App Store odbija pogrešnu dimenziju"
    fi
  done
}

[ "$WANT" = "all" ] || [ "$WANT" = "iphone" ] && \
  capture_set "$(resolve_device 'iPhone 17 Pro Max')" 1320 2868 "iphone-6.9"

[ "$WANT" = "all" ] || [ "$WANT" = "ipad" ] && \
  capture_set "$(resolve_device 'iPad Pro 13-inch')" 2064 2752 "ipad-13"

echo
echo "Gotovo. $OUT"
find "$OUT" -name "*.png" | sort
