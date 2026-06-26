#!/usr/bin/env bash
# Build, (re)launch the simulator, WAIT until the face has actually rendered,
# then screenshot the window. Unlike shot.sh's fixed delay, this detects the
# render, so it is reliable for CI / gallery automation.
#
# How: the sim emits no render-complete event, but the window is the signal.
# Capture a blank baseline (sim up, app not loaded yet), then poll until a frame
# both differs a lot from the baseline (the face appeared) AND barely differs
# from the previous frame (the initial render settled, only the second hand
# moves). Frames are normalised to 240x240 before diffing, so it is device-size
# agnostic and never trips ImageMagick's same-size requirement.
#
# Usage:  auto-shot.sh [device] [out.png]      (defaults: fenix843mm, shot.png)
# Env:    DEVELOPER_KEY  dev key (default: ~/.connectiq/developer_key.der)
#
# Requires: CIQ toolchain on PATH (or the SDK manager CLI to add it), ImageMagick
# (`magick`, `import`, `compare`), and `xprop`. The sim is killed and relaunched
# so the baseline is blank and the device is correct (monkeydo cannot switch a
# running sim's device); on Wayland it is launched under GDK_BACKEND=x11 so its
# X11 window is findable. To just load a build without screenshotting, use shot.sh
# / simrun.sh.
set -euo pipefail
export LC_ALL=C   # force '.' decimal in ImageMagick fx output

DEVICE="${1:-fenix843mm}"
OUT="${2:-shot.png}"
KEY="${DEVELOPER_KEY:-$HOME/.connectiq/developer_key.der}"

JUNGLE="$(ls ./*.jungle 2>/dev/null | head -1 || true)"
[ -n "$JUNGLE" ] || { echo "no .jungle file in $(pwd)" >&2; exit 1; }
NAME="$(basename "$JUNGLE" .jungle)"

if command -v connect-iq-sdk-manager-cli >/dev/null 2>&1; then
  PATH="$(connect-iq-sdk-manager-cli sdk current-path --bin):$PATH"
fi

mkdir -p bin
echo "building $NAME for $DEVICE..."
monkeyc -d "$DEVICE" -f "$JUNGLE" -o "bin/$NAME-$DEVICE.prg" -y "$KEY" -w

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Capture the sim's X11 window (found by WM_NAME) to $1; non-zero if not found.
capture() {
  local id win=""
  for id in $(xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -oE '0x[0-9a-f]+'); do
    if xprop -id "$id" WM_NAME 2>/dev/null | grep -qi 'CIQ Simulator'; then win="$id"; break; fi
  done
  [ -n "$win" ] || return 1
  import -window "$win" "$1" 2>/dev/null
}

echo "restarting simulator (fresh blank baseline + correct device)..."
pkill -f 'bin/simulato[r]' 2>/dev/null || true; sleep 2
setsid env GDK_BACKEND=x11 simulator >/tmp/ciqsim.log 2>&1 </dev/null &
for _ in $(seq 1 80); do ss -ltn 2>/dev/null | grep -q ':1234' && break; sleep 0.3; done

# Blank baseline: the sim window before the app is loaded (retry until it exists).
for _ in $(seq 1 12); do capture "$TMP/base.png" && break; sleep 0.5; done

echo "loading app..."
> /tmp/monkeydo.log
setsid monkeydo "bin/$NAME-$DEVICE.prg" "$DEVICE" >/tmp/monkeydo.log 2>&1 </dev/null &

# Changed-pixel count between two frames, each normalised to 240x240 first.
N=57600   # 240*240
pct() {
  magick "$1" -resize 240x240\! "$TMP/a.png" 2>/dev/null
  magick "$2" -resize 240x240\! "$TMP/b.png" 2>/dev/null
  magick compare -metric AE -fuzz 8% "$TMP/a.png" "$TMP/b.png" null: 2>&1 \
    | grep -oE '^[0-9]+' | head -1 || echo "$N"
}

echo "waiting for render (differs from blank, then settles)..."
prev="$TMP/base.png"; ready=0
for t in $(seq 1 30); do
  sleep 1
  capture "$TMP/cur.png" || continue
  db=$(pct "$TMP/cur.png" "$TMP/base.png")   # vs blank baseline -> "appeared"
  dp=$(pct "$TMP/cur.png" "$prev")           # vs previous frame  -> "settled"
  if awk -v db="${db:-$N}" -v dp="${dp:-$N}" -v n="$N" \
       'BEGIN{exit !(db/n*100>20 && dp/n*100<2)}'; then
    echo "rendered + settled at ~${t}s"; ready=1; break
  fi
  cp "$TMP/cur.png" "$TMP/prev.png"; prev="$TMP/prev.png"
done
[ "$ready" = 1 ] || echo "WARN: render not confirmed within 30s; capturing anyway" >&2

capture "$OUT" && echo "wrote $OUT" || { echo "capture failed (sim window not found)" >&2; exit 1; }
