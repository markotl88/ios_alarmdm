#!/bin/bash
# Captures App Store screenshots at native 6.9" resolution (1320x2868).
#
# Only the 6.9" set is required — App Store Connect scales it down for smaller
# devices. Capturing from the simulator at native size means no scaling at all.
#
#   ./tools/screenshots.sh
#
# Navigate the simulator to each screen, then press Return here.

set -e
DEVICE="${DEVICE:-iPhone 17 Pro Max}"
OUT="${OUT:-$HOME/Desktop/AlarmDM-screenshots}"

SHOTS=(
  "01-radio:Radio tab, kartica sa kasetofonom"
  "02-emisije:Tab Emisije, lista"
  "03-player:Full screen player, epizoda u toku"
  "04-epizode:Lista epizoda jedne emisije, sa filterima"
  "05-podrzi:Tab Podrži"
)

mkdir -p "$OUT"
echo "Uređaj: $DEVICE"
echo "Izlaz:  $OUT"
echo

xcrun simctl boot "$DEVICE" 2>/dev/null || true
open -a Simulator
sleep 3

for entry in "${SHOTS[@]}"; do
  name="${entry%%:*}"
  desc="${entry#*:}"
  printf "→ %s\n  postavi ekran: %s\n  Return za snimanje, s za preskakanje: " "$name" "$desc"
  read -r answer
  [ "$answer" = "s" ] && { echo "  preskočeno"; continue; }

  xcrun simctl io booted screenshot "$OUT/$name.png" >/dev/null 2>&1
  w=$(sips -g pixelWidth "$OUT/$name.png" | awk '/pixelWidth/{print $2}')
  h=$(sips -g pixelHeight "$OUT/$name.png" | awk '/pixelHeight/{print $2}')
  if [ "$w" = "1320" ] && [ "$h" = "2868" ]; then
    echo "  ✓ $w×$h"
  else
    echo "  ⚠ $w×$h — App Store traži 1320×2868 za 6.9\", proveri da je simulator $DEVICE"
  fi
done

echo
echo "Gotovo. Slike su u $OUT"
ls -1 "$OUT"
