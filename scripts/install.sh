#!/usr/bin/env bash
#
# Sideload the watch face onto a physical Garmin device over USB/MTP.
#
# Builds the device-specific .prg if needed, then copies it into GARMIN/Apps
# on the watch. Run from a project directory (it auto-detects the *.jungle).
#
# Usage:
#   install.sh [DEVICE] [PRG]
# Examples:
#   install.sh                         # fenix843mm (default); builds bin/<name>-<dev>.prg
#   install.sh fenix847mm
#   install.sh marq2 bin/<name>-dev-marq2.prg   # sideload a specific prebuilt .prg
#
# With an explicit PRG (arg 2) the file must already exist; without it the
# default .prg is built from the project's .jungle if missing.
#
# Build the .prg for the EXACT device on the watch. Use a separate dev app id
# for sideload so it doesn't collide with a store or beta install.
#
# Prereqs: watch plugged in via USB, unlocked, "allow file transfer" accepted.
# Needs gio (gvfs MTP backend) for the copy.
set -euo pipefail

DEVICE="${1:-fenix843mm}"
KEY="${DEVELOPER_KEY:-$HOME/.connectiq/developer_key.der}"

JUNGLE="$(ls ./*.jungle 2>/dev/null | head -1 || true)"
if [ -z "$JUNGLE" ]; then
  echo "no .jungle file in $(pwd)" >&2
  exit 1
fi
NAME="$(basename "$JUNGLE" .jungle)"
PRG="${2:-bin/$NAME-$DEVICE.prg}"

log() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# 1. Make sure the .prg exists (build it if missing).
if [ ! -f "$PRG" ]; then
  [ -z "${2:-}" ] || die "specified .prg not found: $PRG (build it first)"
  [ -f "$KEY" ] || die "developer key not found at $KEY"
  if command -v connect-iq-sdk-manager-cli >/dev/null 2>&1; then
    PATH="$(connect-iq-sdk-manager-cli sdk current-path --bin):$PATH"
  fi
  log "no prebuilt .prg for '$DEVICE' — building it"
  mkdir -p bin
  monkeyc -d "$DEVICE" -f "$JUNGLE" -o "$PRG" -y "$KEY" -w
fi
log "sideloading $(basename "$PRG") ($(stat -c%s "$PRG") bytes) -> $DEVICE"

# 2. Locate the MTP mount, mounting the watch if needed.
GVFS_DIR="/run/user/$(id -u)/gvfs"
find_mount() { ls -d "$GVFS_DIR"/mtp* 2>/dev/null | head -1 || true; }

DEV="$(find_mount)"
if [ -z "$DEV" ]; then
  log "no MTP mount yet — trying to mount the watch"
  uri="$(gio mount -li 2>/dev/null | grep -oE 'mtp://[^ ]+' | head -1 || true)"
  [ -n "$uri" ] && gio mount "$uri" >/dev/null 2>&1 || true
  for _ in $(seq 1 15); do
    DEV="$(find_mount)"
    [ -n "$DEV" ] && break
    sleep 1
  done
fi
[ -n "$DEV" ] || die "watch not found. Plug in via USB, unlock it, accept 'allow file transfer', then retry."
log "MTP mount: $DEV"

# 3. Find the storage root that holds GARMIN/Apps.
APPS=""
for store in "$DEV"/*; do
  for d in "GARMIN/Apps" "GARMIN/APPS" "Garmin/Apps"; do
    if [ -d "$store/$d" ]; then APPS="$store/$d"; break 2; fi
  done
done
[ -n "$APPS" ] || die "could not locate GARMIN/Apps on the device. Storage roots seen:
$(ls -d "$DEV"/* 2>/dev/null || true)"
log "target folder: $APPS"

# 4. Copy the .prg (gio handles MTP better than plain cp).
DEST="$APPS/$(basename "$PRG")"
if gio copy "$PRG" "$DEST" 2>/dev/null || cp "$PRG" "$DEST"; then
  log "copied to device."
else
  die "copy failed. Check free space on the watch, or copy via a file manager."
fi

# 5. Flush and unmount so it's safe to unplug.
sync 2>/dev/null || true
gio mount -u "$DEV" >/dev/null 2>&1 || true

log "done"
echo "Unplug the watch, then select the face from the watch-face list (long-press"
echo "UP -> Watch Face, or via Connect IQ)."
