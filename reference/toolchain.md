# Toolchain: build and run

## Contents
- SDK and dev key
- Manifest and jungle
- Build and load into the simulator
- Devices must be downloaded with fonts
- Running the simulator (incl. Wayland, headless and container use)
- Sideloading to a real watch

## SDK and dev key

The Connect IQ SDK provides `monkeyc` (compiler) and `monkeydo` (load into the running sim). You can manage SDK versions with the GUI SDK Manager or the open-source CLI `connect-iq-sdk-manager-cli`:

```bash
# put the active SDK's bin on PATH
export PATH="$(connect-iq-sdk-manager-cli sdk current-path --bin):$PATH"
```

On a fresh machine, `scripts/setup-connectiq.sh [sdk-version] [manifest.xml]` bootstraps the whole CLI toolchain end to end: it generates (or reuses) the dev key, installs `connect-iq-sdk-manager-cli` via `go install`, logs in, accepts the EULA, and downloads an SDK plus the devices referenced by a manifest (with fonts). This avoids the GUI SDK Manager, whose prebuilt binary needs `libwebkit2gtk-4.0` (dropped on Arch/Manjaro).

Note the CLI only replaces the *manager*: the **simulator binary itself also links `libwebkit2gtk-4.0.so.37`** (it is a wxWidgets/wxWebView app), so on a distro that ships only webkit2gtk-4.1 the sim will not start no matter how the SDK was installed (`monkeyc` builds still work — it is Java). Fixes: a distro package that still provides the 4.0 ABI (e.g. the AUR `webkit2gtk` package; a 4.1 symlink will NOT work, different ABI), or run the toolchain in a container/VM whose OS still ships 4.0 (Ubuntu 22.04, Debian bookworm — not Ubuntu 24.04). See "Headless and container use" below for making the sim work there, and <https://github.com/wistrand/garmin-dev> for a ready-made container env implementing all of it.

A developer key is required to build. Generate one once and reuse it; for a published app the key must stay constant across releases.

Always check for an existing key before creating a new one — overwriting it breaks the published-app identity. Only generate if none exists:

```bash
if [ ! -f ~/.connectiq/developer_key.der ]; then
  mkdir -p ~/.connectiq
  openssl genrsa -out ~/.connectiq/developer_key.pem 4096
  openssl pkcs8 -topk8 -inform PEM -outform DER -in ~/.connectiq/developer_key.pem \
    -out ~/.connectiq/developer_key.der -nocrypt
fi
```

Keep the `.der` somewhere stable (e.g. `~/.connectiq/developer_key.der`).

## Manifest and jungle

- `manifest.xml` declares the app: a unique app id, the entry type (`watchface`), `minApiLevel`, the list of `<iq:product>` device ids, and permissions.
- `<name>.jungle` declares the build: `base.sourcePath`, `base.resourcePath`, and any per-device overrides. CIQ compiles every `*.xml` under the resource path recursively, so keep exactly one settings file (a stray duplicate silently double-compiles and only fails when the two drift).
- The **app id is the device identity**, not the name. A published app and a beta build cannot share an id, so a project that ships a beta channel keeps separate ids (separate manifests/jungles) that coexist on a watch (see [publishing.md](publishing.md)).

### Per-device launcher icons

The manifest's `launcherIcon` is a single drawable, but devices want the icon at **different native pixel sizes** and a mismatch triggers a launcher-icon scale warning (and a blurry icon). Fix it by **appending a per-device `resourcePath`** in the jungle, so each device picks up a different `LauncherIcon` drawable at its native size with no manifest duplication:

```
# extra resource dirs, each holding drawables/ with a LauncherIcon at that size
fenix843mm.resourcePath = $(fenix843mm.resourcePath);resources-launcher/60
fenix847mm.resourcePath = $(fenix847mm.resourcePath);resources-launcher/65
venu3.resourcePath      = $(venu3.resourcePath);resources-launcher/70
```

A drawable id defined in an appended path overrides the base one for that device. The required size per device is the launcher icon dimension from its `simulator.json` (or just read it off the scale warning). The base `resources/` still provides the fallback icon for any device without an override.

## Build and load into the simulator

```bash
monkeyc -d <device> -f <name>.jungle -o bin/app-<device>.prg \
  -y ~/.connectiq/developer_key.der -w
connectiq &                                   # start the simulator once
monkeydo bin/app-<device>.prg <device>        # load / reload the app
```

`monkeydo` sends only the `.prg`. It cannot switch the device of a running sim — kill and relaunch the sim to change device.

The launcher on PATH is `connectiq` (a small shell wrapper); it execs the actual binary named `simulator`, whose window title is "CIQ Simulator". So `connectiq &`, `pgrep -f simulator`, and the `CIQ Simulator` window all refer to the same process — the bundled scripts use whichever is convenient.

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

### Headless and container use

The sim runs fine in a container or on a headless box (verified: builds, interactive use over VNC, and the screenshot pipeline all work, with output identical to a desktop run). <https://github.com/wistrand/garmin-dev> packages all of the below as a ready-made Docker env (build script, launcher with host-X/headless modes, host shims); the requirements themselves, for rolling your own:

- **A usable DISPLAY is mandatory.** Without one the sim segfaults at GTK init with `Gtk-CRITICAL _gtk_style_provider_private_get_settings` spam — easily misread as a sandbox/security problem. (In Docker, the default seccomp profile is fine and no `WEBKIT_DISABLE_*` variables are needed; software GL via llvmpipe renders correctly.)
- **Headless needs a window manager, not just Xvfb.** Window lookup by title reads `_NET_CLIENT_LIST`, which only a WM populates — run `openbox` (or similar) under Xvfb, and `x11vnc`/noVNC if you want to interact.
- **Use a UTF-8 locale** (`LC_ALL=C.UTF-8` is enough, no locale packages needed). Device window titles contain non-ASCII device names ("fēnix"); under an ASCII locale `xprop` fails the title conversion and the window lookup can silently capture a stale blank window while the face renders perfectly in another.
- **On device load the sim may open a second "CIQ Simulator" window** (seen with Ubuntu 22.04's GTK) and leave the initial blank one listed — match the *last* title hit, not the first (the bundled scripts do).
- Docker specifics: `--shm-size=512m` (the 64 MB default is too small for X rendering), X-socket + xauth passthrough for a desktop window (with the container user matching the host UID so the cookie is valid), and `DEBIAN_FRONTEND=noninteractive` when building images (tzdata's debconf prompt hangs the build invisibly).
- Beware ImageMagick build variance in screenshot tooling: Q16-HDRI builds print `compare -metric AE` counts scaled by 65535 in scientific notation; the bundled `auto-shot.sh` measures changed pixels via a difference composite instead, which is build-independent.

## Sideloading to a real watch

Build a `.prg` for the exact device, then copy it to the watch's `GARMIN/APPS` directory over USB/MTP. Use a separate dev app id for sideload so it does not collide with a store or beta install. App settings on a sideloaded build are configured through Garmin Connect once the watch syncs (see [settings.md](settings.md)). Sideloading is dev-time only; shipping to users is a release `.iq` upload (see [publishing.md](publishing.md)).

`scripts/install.sh [device] [prg]` automates this: it builds the `.prg` if missing, finds the watch's MTP mount (mounting it if needed via `gio`), copies into `GARMIN/Apps`, then flushes and unmounts. The watch must be plugged in, unlocked, with "allow file transfer" accepted. Needs `gio` (gvfs MTP backend). `scripts/uninstall.sh [device]` is the inverse — remove sideloaded `.prg`(s); do this before a beta/store install since a sideload carries the same app id and conflicts.
