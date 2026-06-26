---
name: building-garmin-watchfaces
description: Builds Garmin Connect IQ watch faces in Monkey C — toolchain setup, device capability vetting, always-on (AOD) and sleep handling, performance budgeting, font sizing, app settings, sensor/data sources and permissions, background web fetching, and store publishing. Use when creating, building, configuring, profiling, debugging, or publishing a Garmin watch face or Connect IQ project, or when checking whether a target watch can run a given design.
---

# Building Garmin watch faces

Practical, hard-won guidance for building Connect IQ (CIQ) watch faces in Monkey C, focused on the parts that are non-obvious or device-specific. It assumes Monkey C and CIQ basics; it only captures what tends to cost hours: device capability surprises, always-on/sleep correctness, the per-frame budget, cross-device font sizing, and the settings pipeline.

The reference implementation behind this guidance is an AMOLED analog face (moon/sun ephemeris, radial text, cached buffers). Concrete numbers cite that device set as an example; verify them for your targets with the bundled `vet-device.py`.

## When to reach for what

- New project, or "does device X support this?" → run **Workflow A** (scaffold) and **Workflow B** (vet a device).
- Face renders the low-power style at full brightness, or stays awake draining battery → **Workflow C** (AOD/sleep) and [reference/aod-and-sleep.md](reference/aod-and-sleep.md).
- Slow/janky redraw, out-of-memory, or "can't cache" → [reference/performance.md](reference/performance.md).
- Text the wrong size on one device, or radial/curved text missing → [reference/fonts.md](reference/fonts.md).
- Adding configurable options → [reference/settings.md](reference/settings.md).
- Reading HR/steps/weather/battery/location, or a blank field / permission error → [reference/data-sources.md](reference/data-sources.md).
- Fetching data over the network (background service, `makeWebRequest`, a `-403` / silent no-fetch) → [reference/background-services.md](reference/background-services.md).
- Build/run/sim mechanics → [reference/toolchain.md](reference/toolchain.md).
- Shipping to the store (`.iq` export, beta, updates) → [reference/publishing.md](reference/publishing.md).

## Reference (read on demand)

- [reference/toolchain.md](reference/toolchain.md) — SDK manager CLI, dev key, `monkeyc`/`monkeydo`, jungle + manifest, device download, running the sim (incl. Wayland).
- [reference/device-capabilities.md](reference/device-capabilities.md) — what to vet on a target and why; reading `compiler.json`/`simulator.json`.
- [reference/aod-and-sleep.md](reference/aod-and-sleep.md) — the sleep callback contract, burn-in rules, and recovering from dropped callbacks.
- [reference/performance.md](reference/performance.md) — 128 KB heap vs the graphics pool, the per-frame budget, caching and precompute.
- [reference/fonts.md](reference/fonts.md) — proportional sizing across devices; vector vs bitmap fonts.
- [reference/settings.md](reference/settings.md) — app settings, the value conventions, and the simulator gotchas.
- [reference/data-sources.md](reference/data-sources.md) — reading sensors/activity/weather/battery/location in a face, the permissions they need, and the empty-permissions silent-no-data trap.
- [reference/background-services.md](reference/background-services.md) — fetching web data: the background service shape, makeWebRequest HTTPS/redirect rules, the background memory budget and `-403`, the `(:background)` trap, Storage hand-off, sim temporal-event triggering.
- [reference/publishing.md](reference/publishing.md) — release `.iq` export, key/app-id continuity, store listing, versioning, beta, review pitfalls.

## Setup (once per machine)

Before any build: run `${CLAUDE_SKILL_DIR}/scripts/setup-connectiq.sh [sdk-version] [manifest.xml]` once. It generates (or reuses) the dev key, installs the SDK-manager CLI, logs in, downloads an SDK, and downloads the manifest's devices with fonts. Then put the SDK on PATH (`export PATH="$(connect-iq-sdk-manager-cli sdk current-path --bin):$PATH"`). Details and the manual equivalent: [reference/toolchain.md](reference/toolchain.md).

## Bundled scripts

The scripts are **run in place from the skill directory against your project's current directory** — they auto-detect the project's `*.jungle`, key, and SDK from the cwd and environment, so you do **not** copy them into the project. Two ways to invoke:

- Directly: `${CLAUDE_SKILL_DIR}/scripts/simrun.sh <device>` (or your checkout path) from the project root.
- Via a project `Makefile` whose `SCRIPTS` var points at `${CLAUDE_SKILL_DIR}/scripts` — see `Makefile.template` below.

Copy a script into the project's own `./scripts/` only when you need to **customise** it (e.g. a project-specific gallery/screenshot variant); leave the generic build/run/install ones referenced from the skill so fixes flow through. The `${CLAUDE_SKILL_DIR}` paths below resolve wherever the skill is installed:

- `${CLAUDE_SKILL_DIR}/scripts/setup-connectiq.sh` — bootstrap the CLI toolchain: generate (or reuse) the dev key, install the open-source SDK-manager CLI, log in, download an SDK + the manifest's devices. Run once on a fresh machine.
- `${CLAUDE_SKILL_DIR}/scripts/vet-device.py` — report a device's display/API/graphics-pool/colour/**vector-font** capabilities and assert requirements. Run this before committing to a design or adding a target.
- `${CLAUDE_SKILL_DIR}/scripts/new-project.sh` — scaffold a minimal buildable watch-face project (manifest, jungle, source, resources).
- `${CLAUDE_SKILL_DIR}/scripts/shot.sh` — screenshot a running sim: build, load, wait a fixed delay, capture the window. Use when the sim is already up and you want a quick image.
- `${CLAUDE_SKILL_DIR}/scripts/auto-shot.sh` — same screenshot, but restarts the sim and waits for the render to actually settle (frame-diff detection) instead of a fixed delay. Use for reliable CI / gallery capture.
- `${CLAUDE_SKILL_DIR}/scripts/simrun.sh` — build and load into the sim (launching it if needed), or `--install` to sideload, optionally overriding settings defaults via env vars named after the property ids. Use to (re)run a build, especially with settings overrides. See [reference/settings.md](reference/settings.md).
- `${CLAUDE_SKILL_DIR}/scripts/install.sh` — build (if needed) and sideload the .prg onto a USB-connected watch over MTP. Run from the project dir; defaults to fenix843mm.
- `${CLAUDE_SKILL_DIR}/scripts/uninstall.sh` — remove sideloaded .prg(s) from a USB watch (inverse of install.sh; do this before a beta/store install of the same app id).
- `${CLAUDE_SKILL_DIR}/scripts/gen-settings-doc.py` — generate a Markdown settings reference from `resources/settings/*.xml`.
- `${CLAUDE_SKILL_DIR}/scripts/Makefile.template` — optional one-entry-point wiring (`make build/all/run/shot/install/package/package-beta/…`) over `monkeyc` and the scripts above. Copy it into a project as `Makefile` and edit `NAME`/`DEVICES`/`SCRIPTS` (point `SCRIPTS` at this `${CLAUDE_SKILL_DIR}/scripts` dir). The `package`/`package-beta` targets are the release `.iq` builds (see [reference/publishing.md](reference/publishing.md)).

All scripts are stdlib/shell only and take the SDK and device locations from flags or environment, so they work on any machine with the CIQ toolchain installed.

## Workflow A — scaffold a new watch face

```
- [ ] 1. Pick targets and vet them (Workflow B). Let the weakest device set the design ceiling.
- [ ] 2. Scaffold: scripts/new-project.sh <Name> <primary-device> [target-dir]
        Default device/sim target is fenix843mm (fenix8) unless the user names
        another. Default creates ./<name>/. If the user asks to scaffold "in this dir"
        / "here" / "the current directory", pass "." as target-dir so it
        writes into the current directory with no new subdirectory:
        scripts/new-project.sh <Name> <primary-device> .
- [ ] 3. Build + run in the sim (reference/toolchain.md). Confirm a face renders.
- [ ] 4. Implement drawing in the View's onUpdate; keep the per-frame budget in mind (reference/performance.md).
- [ ] 5. Add always-on/sleep handling early, not last (reference/aod-and-sleep.md).
- [ ] 6. Size text off the dial radius, not getFontHeight (reference/fonts.md).
- [ ] 7. Pull live data (HR/steps/weather/battery/location) and declare the matching
        manifest permissions; null-check every field (reference/data-sources.md).
- [ ] 8. Expose options via resources/settings (reference/settings.md).
- [ ] 9. Ship it: export the release .iq and submit, keeping the key and app id
        constant (reference/publishing.md).
```

Step 1 first: the cheapest time to discover a missing capability (no vector fonts, small graphics pool) is before you write drawing code, not after.

## Workflow B — vet a target device

```
- [ ] 1. Download the device with fonts:
        connect-iq-sdk-manager-cli device download -d <id> --include-fonts
- [ ] 2. Run: scripts/vet-device.py <id>
- [ ] 3. Read the verdict against your design's needs. Decisive ones:
        - display type → burn-in rules apply on AMOLED (reference/aod-and-sleep.md)
        - API level ≥ your manifest minApiLevel
        - graphics pool present + large enough if you cache/bake BufferedBitmaps
        - vector (TTF) fonts present if you draw curved/radial or proportional vector text
- [ ] 4. Assert hard requirements so the check fails loudly, e.g.:
        scripts/vet-device.py <id> --need vector-fonts graphics-pool
```

The single most common late surprise is **a device with no system vector fonts**: any curved/radial text and proportional vector sizing silently disappears there, with no bitmap fallback. `vet-device.py` reports it directly (it detects scalable TTF faces in the device font set).

## Workflow C — debug AOD / sleep symptoms

```
- [ ] 1. Identify the symptom:
        - low-power styling while the screen is at full brightness → a stale sleep flag
          (likely a dropped onExitSleep), see reference/aod-and-sleep.md
        - face never dims / battery drain on AMOLED → not honouring low power / burn-in
        - works in sim, wrong on watch → sim does not enforce the per-update budget or
          deliver real low-power cadence; trust the device
- [ ] 2. Confirm the callback contract: onEnterSleep/onExitSleep drive a single boolean;
        every AOD-dropped element is gated on it.
- [ ] 3. If a dropped callback is suspected, add a cadence-based recovery (the two-path
        pattern in reference/aod-and-sleep.md). There is no API to query power mode.
- [ ] 4. Verify on a real device or a beta install; the simulator cannot reproduce the
        real low-power cadence reliably.
```

## Conventions worth keeping

- The simulator is generous (fast CPU, no per-update execution budget, effectively no memory cap) and its fonts/cadence can differ from hardware. Treat the device as authoritative; verify anything timing-, memory-, or font-sensitive on a real watch or beta install.
- `System.println` lands in `/tmp/monkeydo.log` when run via `monkeydo`. Never leave a per-frame `println` that does real work (e.g. an ephemeris call) in `onUpdate` — it becomes a per-frame regression.
- Watch-face memory is capped at **128 KB** regardless of device tier; `BufferedBitmap`s live in a separate graphics pool. Size memory decisions against the right budget (reference/performance.md).
