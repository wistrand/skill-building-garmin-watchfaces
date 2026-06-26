#!/usr/bin/env bash
# Build + load a watch face into the simulator (or, with --install, sideload it
# to a connected watch), optionally overriding app-settings defaults.
#
# Pass overrides as environment variables named exactly after the <property id>
# entries in resources/settings/properties.xml, e.g.:
#
#     accentColor=0xFF3030 ./simrun.sh fenix843mm        # in the sim
#     showDate=true tz=2 ./simrun.sh fenix847mm          # in the sim
#     accentColor=0xFF3030 ./simrun.sh --install fenix843mm   # sideloaded to the watch
#
# Mechanism: Application.Properties is seeded from the .prg's properties.xml
# defaults. There is no monkeyc flag for this, so for each override we patch the
# default into properties.xml for the build, then restore the file. In the sim we
# also restart it with the persisted .SET store cleared so the new defaults take
# (a new default never overwrites an already-stored property — see settings.md).
#
# Run from the project directory (auto-detects the *.jungle). Defaults: fenix843mm.
set -euo pipefail

INSTALL=0
if [ "${1:-}" = "--install" ]; then INSTALL=1; shift; fi

DEVICE="${1:-fenix843mm}"
KEY="${DEVELOPER_KEY:-$HOME/.connectiq/developer_key.der}"
PROPS="resources/settings/properties.xml"

JUNGLE="$(ls ./*.jungle 2>/dev/null | head -1 || true)"
[ -n "$JUNGLE" ] || { echo "no .jungle file in $(pwd)" >&2; exit 1; }
NAME="$(basename "$JUNGLE" .jungle)"
PRG="bin/$NAME-$DEVICE.prg"
mkdir -p bin

if command -v connect-iq-sdk-manager-cli >/dev/null 2>&1; then
  PATH="$(connect-iq-sdk-manager-cli sdk current-path --bin):$PATH"
fi

# Collect overrides: env vars whose name matches a property id in properties.xml.
ov=()
if [ -f "$PROPS" ]; then
  while read -r id; do
    v="${!id-__UNSET__}"
    [ "$v" = "__UNSET__" ] || ov+=("$id=$v")
  done < <(grep -oE 'id="[a-zA-Z0-9_]+"' "$PROPS" | sed -E 's/id="(.*)"/\1/')
fi

# return 0 so set -e doesn't abort when there's no .bak (no overrides)
restore() { [ -f "$PROPS.bak" ] && mv -f "$PROPS.bak" "$PROPS"; return 0; }

if [ ${#ov[@]} -gt 0 ]; then
  echo ">> settings overrides: ${ov[*]}"
  cp "$PROPS" "$PROPS.bak"; trap restore EXIT
  for kv in "${ov[@]}"; do
    k="${kv%%=*}"; val="${kv#*=}"
    sed -i -E "s#(<property id=\"$k\" type=\"[a-z]+\">)[^<]*(</property>)#\1${val}\2#" "$PROPS"
  done
fi

echo ">> build $DEVICE"
monkeyc -d "$DEVICE" -f "$JUNGLE" -o "$PRG" -y "$KEY" -w >/dev/null
restore; trap - EXIT   # the .prg has baked the defaults; restore properties.xml now

if [ "$INSTALL" = 1 ]; then
  echo ">> sideload to watch"
  INSTALL_SH="$(dirname "$0")/install.sh"
  "$INSTALL_SH" "$DEVICE" "$PRG"
  echo "installed $DEVICE (overrides: ${ov[*]:-none})"
  exit 0
fi

if [ ${#ov[@]} -gt 0 ]; then
  echo ">> restart sim + clear persisted store (so the overridden defaults apply)"
  pkill -f 'bin/simulato[r]' 2>/dev/null || true; sleep 2
  # The sim names the store <APP-NAME>-<DEVICE>.SET (after the manifest display
  # name, not the jungle/prg basename), so match on the device — the one token we
  # know here — rather than guessing the app name. "*-marq2.SET" hits
  # AI-STATUS-MARQ2.SET and won't false-match "*-marq2aviator.SET".
  find /tmp/com.garmin.connectiq -iname "*-${DEVICE}.SET" -delete 2>/dev/null || true
fi

# Launch the sim if it isn't already up (XWayland-friendly), then wait for its port.
pgrep -f 'bin/simulato[r]' >/dev/null \
  || { setsid env GDK_BACKEND=x11 simulator >/tmp/ciqsim.log 2>&1 </dev/null & sleep 5; }
for _ in $(seq 1 60); do ss -ltn 2>/dev/null | grep -q ':1234' && break; sleep 0.3; done

> /tmp/monkeydo.log
setsid monkeydo "$PRG" "$DEVICE" >/tmp/monkeydo.log 2>&1 </dev/null &
echo "loaded $DEVICE (overrides: ${ov[*]:-none}); logs /tmp/monkeydo.log"
