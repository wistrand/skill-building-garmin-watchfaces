#!/usr/bin/env bash
# Scaffold a minimal, buildable Connect IQ watch-face project.
#
# Creates a manifest, jungle, source (App + a trivial analog View with sleep
# handling), and resources (strings + a generated launcher icon) so you can
# build and run immediately, then replace the View's drawing with your own.
#
# Usage:
#   new-project.sh <Name> [device] [target-dir]
#
# Examples:
#   new-project.sh Moonphase
#   new-project.sh Moonphase marq2aviator ./moonphase
#
# Defaults: device=marq2aviator, target-dir=./<name-lowercased>
set -euo pipefail

NAME="${1:-}"
DEVICE="${2:-marq2aviator}"
if [ -z "$NAME" ]; then
  echo "usage: new-project.sh <Name> [device] [target-dir]" >&2
  exit 2
fi
LOWER="$(printf '%s' "$NAME" | tr '[:upper:]' '[:lower:]')"
DIR="${3:-./$LOWER}"

if [ -e "$DIR" ]; then
  echo "refusing to overwrite existing path: $DIR" >&2
  exit 1
fi

# A stable app id is the device identity. Generate one now; freeze it for a
# published app (never regenerate it across releases).
APPID="$(python3 -c 'import uuid; print(uuid.uuid4().hex)')"

mkdir -p "$DIR/source" "$DIR/resources/strings" "$DIR/resources/drawables"

# --- launcher icon (generated solid PNG; replace with your own art) ---------
python3 - "$DIR/resources/drawables/launcher_icon.png" <<'PY'
import sys, struct, zlib
size = 40
# opaque dark-grey RGBA raster with a 1-byte filter prefix per row
row = b"\x00" + bytes((40, 40, 48, 255)) * size
raw = row * size
def chunk(tag, data):
    return (struct.pack(">I", len(data)) + tag + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff))
png = b"\x89PNG\r\n\x1a\n"
png += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(raw, 9))
png += chunk(b"IEND", b"")
open(sys.argv[1], "wb").write(png)
PY

# --- manifest ---------------------------------------------------------------
cat > "$DIR/manifest.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<iq:manifest version="3" xmlns:iq="http://www.garmin.com/xml/connectiq">
    <iq:application id="$APPID" type="watchface" name="@Strings.AppName"
        entry="${NAME}App" launcherIcon="@Drawables.LauncherIcon"
        minApiLevel="3.1.0">
        <iq:products>
            <iq:product id="$DEVICE"/>
        </iq:products>
        <iq:permissions/>
        <iq:languages>
            <iq:language>eng</iq:language>
        </iq:languages>
    </iq:application>
</iq:manifest>
EOF

# --- jungle -----------------------------------------------------------------
cat > "$DIR/$LOWER.jungle" <<EOF
project.manifest = manifest.xml
base.sourcePath = source
base.resourcePath = resources
EOF

# --- resources --------------------------------------------------------------
cat > "$DIR/resources/strings/strings.xml" <<EOF
<strings>
    <string id="AppName">$NAME</string>
</strings>
EOF

cat > "$DIR/resources/drawables/drawables.xml" <<EOF
<drawables>
    <bitmap id="LauncherIcon" filename="launcher_icon.png"/>
</drawables>
EOF

# --- source: App ------------------------------------------------------------
cat > "$DIR/source/${NAME}App.mc" <<EOF
import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class ${NAME}App extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        return [ new ${NAME}View() ];
    }

    function onSettingsChanged() as Void {
        WatchUi.requestUpdate();
    }
}
EOF

# --- source: View (trivial analog face with sleep handling) -----------------
cat > "$DIR/source/${NAME}View.mc" <<EOF
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;

// Minimal analog face. Replace onUpdate's drawing with your own; keep the
// _sleeping gate on anything bright/animated so the always-on view stays
// burn-in safe. See the building-garmin-watchfaces skill for the full design.
class ${NAME}View extends WatchUi.WatchFace {
    private var _sleeping as Boolean = false;

    function initialize() {
        WatchFace.initialize();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();

        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;
        var r = (cx < cy ? cx : cy);
        var t = System.getClockTime();
        var hh = (t.hour % 12) + t.min / 60.0;

        drawHand(dc, cx, cy, (t.min / 60.0) * Math.PI * 2, r * 0.82, 3, Graphics.COLOR_WHITE);
        drawHand(dc, cx, cy, (hh / 12.0) * Math.PI * 2, r * 0.55, 4, Graphics.COLOR_WHITE);

        if (!_sleeping) {
            drawHand(dc, cx, cy, (t.sec / 60.0) * Math.PI * 2, r * 0.88, 2, Graphics.COLOR_RED);
        }
    }

    private function drawHand(dc as Graphics.Dc, cx as Number, cy as Number,
            angle as Float, len as Float, pen as Number, color as Number) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(pen);
        dc.drawLine(cx, cy, cx + len * Math.sin(angle), cy - len * Math.cos(angle));
    }

    function onEnterSleep() as Void {
        _sleeping = true;
        WatchUi.requestUpdate();
    }

    function onExitSleep() as Void {
        _sleeping = false;
        WatchUi.requestUpdate();
    }
}
EOF

echo "Scaffolded $NAME in $DIR (app id $APPID, device $DEVICE)."
echo
echo "Build and run:"
echo "  cd $DIR"
echo "  export PATH=\"\$(connect-iq-sdk-manager-cli sdk current-path --bin):\$PATH\""
echo "  connect-iq-sdk-manager-cli device download -d $DEVICE --include-fonts"
echo "  monkeyc -d $DEVICE -f $LOWER.jungle -o bin/$LOWER-$DEVICE.prg -y ~/.connectiq/developer_key.der -w"
echo "  connectiq &   # start the sim once"
echo "  monkeydo bin/$LOWER-$DEVICE.prg $DEVICE"
