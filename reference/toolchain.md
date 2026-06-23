# Toolchain: build and run

## Contents
- SDK and dev key
- Manifest and jungle
- Build and load into the simulator
- Devices must be downloaded with fonts
- Running the simulator (incl. Wayland)
- Sideloading to a real watch

## SDK and dev key

The Connect IQ SDK provides `monkeyc` (compiler) and `monkeydo` (load into the running sim). You can manage SDK versions with the GUI SDK Manager or the open-source CLI `connect-iq-sdk-manager-cli`:

```bash
# put the active SDK's bin on PATH
export PATH="$(connect-iq-sdk-manager-cli sdk current-path --bin):$PATH"
```

A developer key is required to build. Generate one once and reuse it; for a published app the key must stay constant across releases:

```bash
openssl genrsa -out developer_key.pem 4096
openssl pkcs8 -topk8 -inform PEM -outform DER -in developer_key.pem \
  -out developer_key.der -nocrypt
```

Keep the `.der` somewhere stable (e.g. `~/.connectiq/developer_key.der`).

## Manifest and jungle

- `manifest.xml` declares the app: a unique app id, the entry type (`watchface`), `minApiLevel`, the list of `<iq:product>` device ids, and permissions.
- `<name>.jungle` declares the build: `base.sourcePath`, `base.resourcePath`, and any per-device overrides. CIQ compiles every `*.xml` under the resource path recursively, so keep exactly one settings file (a stray duplicate silently double-compiles and only fails when the two drift).
- The **app id is the device identity**, not the name. A published app and a beta build cannot share an id, so a project that ships a beta channel keeps separate ids (separate manifests/jungles) that coexist on a watch.

## Build and load into the simulator

```bash
monkeyc -d <device> -f <name>.jungle -o bin/app-<device>.prg \
  -y ~/.connectiq/developer_key.der -w
connectiq &                                   # start the simulator once
monkeydo bin/app-<device>.prg <device>        # load / reload the app
```

`monkeydo` sends only the `.prg`. It cannot switch the device of a running sim — kill and relaunch the sim to change device.

## Devices must be downloaded with fonts

Download each target's descriptors and fonts before building or simulating:

```bash
connect-iq-sdk-manager-cli device download -d <id> --include-fonts
```

Without `--include-fonts` the simulator can segfault rendering text. Downloaded devices land under `~/.Garmin/ConnectIQ/Devices/<id>/` (`compiler.json`, `simulator.json`, fonts). Those JSON files are what `vet-device.py` reads.

## Running the simulator

- The sim is generous: fast CPU, no per-`onUpdate` execution budget, effectively no memory limit. It will happily run code that overruns a real watch. Verify timing-, memory-, and font-sensitive behaviour on hardware or a beta install.
- Set sensor inputs from the Simulation menu: heart rate via Health Monitoring; weather/GPS via the Simulation menu (otherwise sun/weather/position fields read as unavailable).
- `System.println` output goes to `/tmp/monkeydo.log` when launched via `monkeydo`.

### Wayland

The simulator is an XWayland client. On GNOME/Wayland, launch it under X11 so window tooling can find it:

```bash
GDK_BACKEND=x11 connectiq &
```

To screenshot, capture the sim's X11 window by id rather than the screen (its title is "CIQ Simulator"); see `scripts/shot.sh`.

## Sideloading to a real watch

Build a `.prg` for the exact device, then copy it to the watch's `GARMIN/APPS` directory over USB/MTP. Use a separate dev app id for sideload so it does not collide with a store or beta install. App settings on a sideloaded build are configured through Garmin Connect once the watch syncs (see [settings.md](settings.md)).
