#!/usr/bin/env bash
# Build, load into the running simulator, and screenshot the sim window.
#
# A simplified port of a fuller auto-shot tool. It builds, loads via monkeydo,
# waits a fixed delay for the face to render, then captures the simulator's X11
# window by id (not the screen), so it works regardless of window position.
#
# Usage:
#   shot.sh [device] [out.png]
#
# Environment:
#   DEVELOPER_KEY  path to the dev key  (default: ~/.connectiq/developer_key.der)
#   SHOT_WAIT      seconds to wait for render before capture (default: 9)
#
# Requires: the CIQ toolchain on PATH (or the SDK manager CLI to add it),
# ImageMagick (`import`), and `xprop` (part of the base X11 tools). The
# simulator must already be running; on Wayland start it with GDK_BACKEND=x11
# so its X11 window is findable. The build device should match the device the
# sim is currently running (monkeydo cannot switch a running sim's device).
set -euo pipefail

DEVICE="${1:-marq2aviator}"
OUT="${2:-shot.png}"
KEY="${DEVELOPER_KEY:-$HOME/.connectiq/developer_key.der}"
WAIT="${SHOT_WAIT:-9}"

JUNGLE="$(ls ./*.jungle 2>/dev/null | head -1 || true)"
if [ -z "$JUNGLE" ]; then
  echo "no .jungle file in $(pwd)" >&2
  exit 1
fi
NAME="$(basename "$JUNGLE" .jungle)"

if command -v connect-iq-sdk-manager-cli >/dev/null 2>&1; then
  PATH="$(connect-iq-sdk-manager-cli sdk current-path --bin):$PATH"
fi

mkdir -p bin
echo "building $NAME for $DEVICE..."
monkeyc -d "$DEVICE" -f "$JUNGLE" -o "bin/$NAME-$DEVICE.prg" -y "$KEY" -w

# monkeydo stays attached to the simulator (it does not return), so run it
# detached and leave it running; the app stays loaded in the sim.
echo "loading into the simulator..."
setsid monkeydo "bin/$NAME-$DEVICE.prg" "$DEVICE" >/tmp/monkeydo.log 2>&1 </dev/null &

echo "waiting ${WAIT}s for the face to render..."
sleep "$WAIT"

# Find the simulator's X11 window id by WM_NAME among managed XWayland clients.
# The sim is an XWayland client, so xprop sees it; capturing by id is immune to
# the window moving and reads the window's backing pixmap directly.
WIN=""
for id in $(xprop -root _NET_CLIENT_LIST 2>/dev/null | grep -oE '0x[0-9a-f]+'); do
  if xprop -id "$id" WM_NAME 2>/dev/null | grep -qi 'CIQ Simulator'; then
    WIN="$id"
    break
  fi
done
if [ -z "$WIN" ]; then
  echo "no 'CIQ Simulator' window found (is the sim running under X11?)" >&2
  exit 1
fi

import -window "$WIN" "$OUT"
echo "wrote $OUT (sim window $WIN)"
