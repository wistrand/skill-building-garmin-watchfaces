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
# ImageMagick (`import`), and xdotool. The simulator must already be running;
# on Wayland start it with GDK_BACKEND=x11 so its X11 window is findable.
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
echo "loading into the simulator..."
monkeydo "bin/$NAME-$DEVICE.prg" "$DEVICE"

echo "waiting ${WAIT}s for the face to render..."
sleep "$WAIT"

WIN="$(xdotool search --name 'CIQ Simulator' 2>/dev/null | head -1 || true)"
if [ -z "$WIN" ]; then
  echo "could not find the 'CIQ Simulator' window (is the sim running under X11?)" >&2
  exit 1
fi

import -window "$WIN" "$OUT"
echo "wrote $OUT"
