#!/usr/bin/env bash
#
# Remove sideloaded .prg(s) from a Garmin device over USB/MTP. The inverse of
# install.sh. Handy before a store/beta install: a sideloaded copy carries the
# same app id and conflicts with the beta install.
#
# Run from the project directory (it auto-detects the *.jungle for the name).
#
# Usage:
#   uninstall.sh           # remove ALL <name>-*.prg on the watch (default)
#   uninstall.sh fenix843mm   # remove only <name>-fenix843mm.prg
#
# Prereqs: watch plugged in via USB, unlocked, "allow file transfer" accepted.
# Needs gio (gvfs MTP backend).
set -euo pipefail

DEVICE="${1:-}"

JUNGLE="$(ls ./*.jungle 2>/dev/null | head -1 || true)"
if [ -z "$JUNGLE" ]; then
  echo "no .jungle file in $(pwd)" >&2
  exit 1
fi
NAME="$(basename "$JUNGLE" .jungle)"

log() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# 1. Locate the MTP mount, mounting the watch if needed (same as install.sh).
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

# 2. Find the storage root that holds GARMIN/Apps.
APPS=""
for store in "$DEV"/*; do
  for d in "GARMIN/Apps" "GARMIN/APPS" "Garmin/Apps"; do
    if [ -d "$store/$d" ]; then APPS="$store/$d"; break 2; fi
  done
done
[ -n "$APPS" ] || die "could not locate GARMIN/Apps on the device."
log "app folder: $APPS"

# 3. Collect the .prg(s) to remove.
matches=()
if [ -z "$DEVICE" ] || [ "$DEVICE" = "all" ]; then
  for f in "$APPS/$NAME"-*.prg; do [ -e "$f" ] && matches+=("$f"); done
  label="all $NAME builds"
else
  f="$APPS/$NAME-$DEVICE.prg"
  [ -e "$f" ] && matches+=("$f")
  label="$NAME-$DEVICE.prg"
fi

if [ ${#matches[@]} -eq 0 ]; then
  log "no $label found on the device (already uninstalled?)."
  present=""
  for f in "$APPS/$NAME"-*.prg; do [ -e "$f" ] && present+="  $(basename "$f")\n"; done
  [ -n "$present" ] && printf "%s files present:\n%b" "$NAME" "$present"
else
  for f in "${matches[@]}"; do
    if gio rm "$f" 2>/dev/null || rm -f "$f"; then
      log "removed $(basename "$f")"
    else
      die "failed to remove $f (is the watch unlocked / not busy?)."
    fi
  done
fi

# 4. Flush and unmount so it's safe to unplug.
sync 2>/dev/null || true
gio mount -u "$DEV" >/dev/null 2>&1 || true

log "done. Unplug the watch."
