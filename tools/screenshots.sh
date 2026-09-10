#!/bin/bash
# Captures App Store screenshots at native resolution.
#
#   iPhone 6.9"  1320x2868   (17 Pro Max / 16 Pro Max / 15 Pro Max class)
#   iPad   13"   2064x2752   (iPad Pro 13-inch)
#
# App Store Connect scales those down for every smaller device itself.
#
#   ./tools/screenshots.sh            both
#   ./tools/screenshots.sh iphone
#   ./tools/screenshots.sh ipad
#   ./tools/screenshots.sh list       just show what is installed

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

# Several device generations share a screen size. First one installed wins.
IPHONE_CANDIDATES=("iPhone 17 Pro Max" "iPhone 16 Pro Max" "iPhone 15 Pro Max" "iPhone 14 Pro Max")
IPAD_CANDIDATES=("iPad Pro 13-inch" "iPad Pro (12.9-inch)")

available_devices() {
  xcrun simctl list devices available | grep -E "^ +(iPhone|iPad)" | sed 's/^ *//'
}

# Prints "UDID<TAB>Name" for the first candidate that is installed.
resolve_device() {
  local candidate line udid name
  for candidate in "$@"; do
    line=$(xcrun simctl list devices available | grep -F "$candidate (" | head -1) || true
    if [ -n "$line" ]; then
      udid=$(echo "$line" | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
      name=$(echo "$line" | sed -E 's/^ *(.*[^ ]) +\([0-9A-F-]{36}\).*/\1/')
      printf '%s\t%s\n' "$udid" "$name"
      return
    fi
  done
}

capture_set() {
  local expect_w="$1" expect_h="$2" folder="$3"; shift 3
  local resolved udid name
  resolved=$(resolve_device "$@")

  if [ -z "$resolved" ]; then
    echo
    echo "⚠ nijedan od ovih simulatora nije instaliran: $*"
    echo "  instaliraj u Xcode → Settings → Components, ili snimi na drugom uređaju"
    echo "  (dimenzija mora biti tačno ${expect_w}×${expect_h})"
    echo
    echo "  imaš ove:"
    available_devices | sed 's/^/    /'
    return
  fi

  udid="${resolved%%$'\t'*}"
  name="${resolved#*$'\t'}"

  # One simulator running at a time: no doubt about which window is being shot.
  xcrun simctl shutdown all 2>/dev/null || true
  xcrun simctl boot "$udid" 2>/dev/null || true
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || true
  open -a Simulator
  sleep 3

  mkdir -p "$OUT/$folder"
  echo
  echo "════ $folder"
  echo "     $name"
  echo "     $udid  →  ${expect_w}×${expect_h}"
  echo "     pokreni aplikaciju na ovom simulatoru pre prvog snimka"

  for entry in "${SHOTS[@]}"; do
    local shot="${entry%%:*}" desc="${entry#*:}"
    printf "\n→ %s\n  postavi ekran: %s\n  Return za snimanje, s za preskakanje: " "$shot" "$desc"
    read -r answer
    [ "$answer" = "s" ] && { echo "  preskočeno"; continue; }

    xcrun simctl io "$udid" screenshot "$OUT/$folder/$shot.png" >/dev/null 2>&1
    local w h
    w=$(sips -g pixelWidth "$OUT/$folder/$shot.png" | awk '/pixelWidth/{print $2}')
    h=$(sips -g pixelHeight "$OUT/$folder/$shot.png" | awk '/pixelHeight/{print $2}')
    if [ "$w" = "$expect_w" ] && [ "$h" = "$expect_h" ]; then
      echo "  ✓ $w×$h"
    else
      echo "  ⚠ $w×$h umesto ${expect_w}×${expect_h} — App Store odbija pogrešnu dimenziju"
    fi
  done
}

if [ "$WANT" = "list" ]; then
  echo "Dostupni simulatori:"
  available_devices | sed 's/^/  /'
  exit 0
fi

if [ "$WANT" = "all" ] || [ "$WANT" = "iphone" ]; then
  capture_set 1320 2868 "iphone-6.9" "${IPHONE_CANDIDATES[@]}"
fi
if [ "$WANT" = "all" ] || [ "$WANT" = "ipad" ]; then
  capture_set 2064 2752 "ipad-13" "${IPAD_CANDIDATES[@]}"
fi

echo
echo "Gotovo. $OUT"
find "$OUT" -name "*.png" ! -path "*/framed/*" -exec sh -c \
  'printf "  %-34s " "${1#*AlarmDM-screenshots/}"; sips -g pixelWidth -g pixelHeight "$1" | awk "/pixel/{printf \$2\" \"}"; echo' _ {} \; | sort
