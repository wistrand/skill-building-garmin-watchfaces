#!/usr/bin/env python3
"""Vet a Garmin Connect IQ device for watch-face capabilities.

Reads the device descriptors that the Connect IQ SDK Manager downloads
(compiler.json + simulator.json) and reports the capabilities that decide
whether a watch-face design will run on that device:

  - display type (amoled / memory-in-pixel) and burn-in implications
  - Connect IQ API level (vs your manifest minApiLevel)
  - graphics pool (enhancedGraphicSupport + graphicsResourcePoolSize) for
    BufferedBitmap caching and image baking
  - colour depth and alpha blending
  - system VECTOR (scalable TTF) fonts, required for curved/radial text and
    proportional vector sizing; their ABSENCE silently drops such fields

Download a device first (descriptors + fonts):
    connect-iq-sdk-manager-cli device download -d <id> --include-fonts

Usage:
    vet-device.py <device-id> [<device-id> ...]
    vet-device.py --list
    vet-device.py venu2 --need vector-fonts graphics-pool
    vet-device.py venu2 --need api>=4.2.1

Exit status is non-zero if any requested --need capability is missing on any
listed device, so it can guard a build or CI step.
"""

import argparse
import json
import os
import sys

# Default location the SDK Manager writes downloaded devices to. Override with
# --devices-dir or the GARMIN_DEVICES_DIR environment variable.
DEFAULT_DEVICES_DIR = os.path.expanduser(
    os.environ.get("GARMIN_DEVICES_DIR", "~/.Garmin/ConnectIQ/Devices")
)

# Standard bitmap font names present on every device. A device with scalable
# system fonts additionally lists TTF-typed entries / named faces beyond these.
STANDARD_FONT_NAMES = {
    "xtiny", "tiny", "small", "medium", "large",
    "numberMild", "numberMedium", "numberHot", "numberThaiHot",
    "glanceFont", "glanceNumberFont",
}


def load_json(path):
    """Load a JSON file, returning {} with a warning rather than crashing."""
    try:
        with open(path) as fh:
            return json.load(fh)
    except FileNotFoundError:
        return None
    except (OSError, ValueError) as exc:
        print(f"  warning: could not read {path}: {exc}", file=sys.stderr)
        return {}


def parse_version(text):
    """Parse a dotted version like '4.2.1' into a comparable tuple."""
    parts = []
    for chunk in str(text).split("."):
        digits = "".join(c for c in chunk if c.isdigit())
        parts.append(int(digits) if digits else 0)
    return tuple(parts) or (0,)


def api_level(compiler):
    """Highest connectIQVersion across the device's part numbers."""
    best = None
    for part in compiler.get("partNumbers", []) or []:
        ver = part.get("connectIQVersion")
        if ver and (best is None or parse_version(ver) > parse_version(best)):
            best = ver
    return best


def font_table(simulator):
    """Return the 'ww' (worldwide) font list, or [] if absent."""
    for entry in simulator.get("fonts", []) or []:
        if entry.get("fontSet") == "ww":
            return entry.get("fonts", []) or []
    return []


def vector_faces(simulator):
    """Named scalable (TTF) faces a device exposes to getVectorFont.

    A device with scalable system fonts has font entries typed 'ttf' and named
    faces beyond the standard bitmap set. Bitmap-only devices have neither.
    Returns a sorted list of face names (empty => no system vector fonts).
    """
    faces = set()
    any_ttf = False
    for font in font_table(simulator):
        if not isinstance(font, dict):
            continue
        if font.get("type") == "ttf":
            any_ttf = True
        name = font.get("name")
        if name and name not in STANDARD_FONT_NAMES and not name.startswith("system"):
            faces.add(name)
    # If entries are TTF-typed but only carry standard names, still report the
    # capability via a sentinel so the verdict is correct.
    if any_ttf and not faces:
        faces.add("(scalable system fonts)")
    return sorted(faces)


def vet(device_id, devices_dir):
    """Gather capabilities for one device. Returns a dict or None if missing."""
    ddir = os.path.join(devices_dir, device_id)
    compiler = load_json(os.path.join(ddir, "compiler.json"))
    simulator = load_json(os.path.join(ddir, "simulator.json"))
    if compiler is None and simulator is None:
        return None
    compiler = compiler or {}
    simulator = simulator or {}

    res = compiler.get("resolution") or {}
    faces = vector_faces(simulator)
    return {
        "id": device_id,
        "display": compiler.get("displayType"),
        "resolution": (res.get("width"), res.get("height")),
        "bpp": compiler.get("bitsPerPixel"),
        "api": api_level(compiler),
        "graphics_pool": bool(compiler.get("enhancedGraphicSupport")),
        "pool_bytes": simulator.get("graphicsResourcePoolSize"),
        "alpha": bool(compiler.get("alphaBlendingSupport")),
        "vector_faces": faces,
    }


def fmt_bytes(n):
    if not isinstance(n, (int, float)):
        return "?"
    return f"{n / (1024 * 1024):.1f} MB"


def report(cap):
    res = cap["resolution"]
    res_s = f"{res[0]}x{res[1]}" if res[0] else "?"
    print(f"== {cap['id']} ==")
    print(f"  display          : {cap['display'] or '?'}")
    print(f"  resolution       : {res_s}")
    print(f"  colour depth     : {cap['bpp'] or '?'} bpp")
    print(f"  API level        : {cap['api'] or '?'}")
    print(f"  graphics pool    : {'yes' if cap['graphics_pool'] else 'NO'}"
          f"  ({fmt_bytes(cap['pool_bytes'])})")
    print(f"  alpha blending   : {'yes' if cap['alpha'] else 'NO'}")
    if cap["vector_faces"]:
        print(f"  vector fonts     : yes  ({', '.join(cap['vector_faces'])})")
    else:
        print(f"  vector fonts     : NO  -> radial/curved text would vanish here")
    print()


def check_need(cap, need):
    """Return (ok, message) for one --need token against one device."""
    token = need.lower()
    if token == "amoled":
        return cap["display"] == "amoled", "display is not amoled"
    if token == "vector-fonts":
        return bool(cap["vector_faces"]), "no system vector fonts"
    if token == "graphics-pool":
        return cap["graphics_pool"], "no graphics pool (enhancedGraphicSupport)"
    if token == "alpha":
        return cap["alpha"], "no alpha blending"
    if token.startswith("api>="):
        want = token[len("api>="):]
        have = cap["api"]
        ok = bool(have) and parse_version(have) >= parse_version(want)
        return ok, f"API {have or '?'} < required {want}"
    return False, f"unknown requirement '{need}'"


def main():
    ap = argparse.ArgumentParser(
        description="Vet Garmin Connect IQ devices for watch-face capabilities.",
    )
    ap.add_argument("devices", nargs="*", help="device id(s), e.g. venu2 fenix843mm")
    ap.add_argument("--devices-dir", default=DEFAULT_DEVICES_DIR,
                    help=f"SDK devices directory (default: {DEFAULT_DEVICES_DIR})")
    ap.add_argument("--need", nargs="+", default=[], metavar="CAP",
                    help="require capabilities; non-zero exit if missing. "
                         "One of: amoled vector-fonts graphics-pool alpha api>=X.Y.Z")
    ap.add_argument("--list", action="store_true",
                    help="list downloaded device ids and exit")
    args = ap.parse_args()

    if args.list:
        try:
            ids = sorted(d for d in os.listdir(args.devices_dir)
                         if os.path.isdir(os.path.join(args.devices_dir, d)))
        except OSError as exc:
            print(f"cannot list {args.devices_dir}: {exc}", file=sys.stderr)
            return 2
        print("\n".join(ids) if ids else "(no devices downloaded)")
        return 0

    if not args.devices:
        ap.print_usage()
        print("\nNo device id given. Use --list to see downloaded devices.",
              file=sys.stderr)
        return 2

    failures = 0
    for device_id in args.devices:
        cap = vet(device_id, args.devices_dir)
        if cap is None:
            print(f"== {device_id} ==")
            print(f"  not found under {args.devices_dir}")
            print(f"  download it: connect-iq-sdk-manager-cli device download "
                  f"-d {device_id} --include-fonts\n")
            failures += 1
            continue
        report(cap)
        for need in args.need:
            ok, why = check_need(cap, need)
            if not ok:
                print(f"  REQUIREMENT FAILED [{device_id}]: {need} -> {why}")
                failures += 1

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
