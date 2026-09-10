#!/bin/bash
# Captures App Store screenshots at native resolution for both required sets.
#
#   iPhone 6.9"  1320x2868
#   iPad   13"   2064x2752
#
# App Store Connect scales those down for smaller devices itself.
#
#   ./tools/screenshots.sh          both
#   ./tools/screenshots.sh iphone
#   ./tools/screenshots.sh ipad

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

# Returns "UDID<TAB>Name" for the first available simulator matching $1.
resolve_device() {
  xcrun simctl list devices available \
    | grep -E "^ +$1[^(]*\(" \
    | head -1 \
    | sed -E 's/^ *(.*[^ ]) +\(([-A-F0-9]+)\).*/\2\t\1/'
}

capture_set() {
  local pattern="$1" expect_w="$2" expect_h="$3" folder="$4"
  local resolved udid name
  resolved=$(resolve_device "$pattern")

  if [ -z "$resolved" ]; then
    echo "⚠ nema simulatora koji odgovara \"$pattern\" — preskačem $folder"
    echo "  instaliraj ga u Xcode → Settings → Components"
    return
  fi

  udid="${resolved%%$'\t'*}"
  name="${resolved#*$'\t'}"

  mkdir -p "$OUT/$folder"
  echo
  echo "════ $folder — $name"
  echo "     $udid  (očekivano $expect_w×$expect_h)"

  # Every capture targets this UDID explicitly. "booted" grabs whichever
  # simulator happens to be running, which silently produces the wrong device.
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
  open -a Simulator
  sleep 2

  for entry in "${SHOTS[@]}"; do
    local shot="${entry%%:*}" desc="${entry#*:}"
    printf "→ %s\n  postavi ekran: %s\n  Return za snimanje, s za preskakanje: " "$shot" "$desc"
    read -r answer
    [ "$answer" = "s" ] && { echo "  preskočeno"; continue; }

    xcrun simctl io "$udid" screenshot "$OUT/$folder/$shot.png" >/dev/null 2>&1
    local w h
    w=$(sips -g pixelWidth "$OUT/$folder/$shot.png" | awk '/pixelWidth/{print $2}')
    h=$(sips -g pixelHeight "$OUT/$folder/$shot.png" | awk '/pixelHeight/{print $2}')
    if [ "$w" = "$expect_w" ] && [ "$h" = "$expect_h" ]; then
      echo "  ✓ $w×$h"
    else
      echo "  ⚠ $w×$h umesto $expect_w×$expect_h — App Store odbija pogrešnu dimenziju"
    fi
  done
}

if [ "$WANT" = "all" ] || [ "$WANT" = "iphone" ]; then
  capture_set "iPhone 17 Pro Max" 1320 2868 "iphone-6.9"
fi
if [ "$WANT" = "all" ] || [ "$WANT" = "ipad" ]; then
  capture_set "iPad Pro 13-inch" 2064 2752 "ipad-13"
fi

echo
echo "Gotovo. $OUT"
find "$OUT" -name "*.png" -exec sh -c 'printf "%s  " "$1"; sips -g pixelWidth -g pixelHeight "$1" | awk "/pixel/{printf \$2\" \"}"; echo' _ {} \; | sort
