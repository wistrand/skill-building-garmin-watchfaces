# Publishing a watch face

## Contents
- The release package (.iq)
- Key and app-id continuity
- Store listing and supported devices
- Versioning and updates
- Multi-channel builds (dev / beta / production)
- Review and common rejections

## The release package (.iq)

The store does not take a `.prg`. You upload a single `.iq` bundle that contains one build per `<iq:product>` in the manifest plus the store metadata. Export it with `monkeyc` (or VS Code's "Export Project"):

```bash
monkeyc -f <name>.jungle -o bin/<name>.iq -y ~/.connectiq/developer_key.der -e -r
```

- `-e` packages an exported `.iq` (all products) rather than a single-device `.prg`.
- `-r` adds release optimization (no debug info); keep `-w` (warnings) on alongside it — the release build is `-w -r`, not one instead of the other.

Build the beta channel the same way from its jungle: `monkeyc -e -r -w -f app-beta.jungle -o bin/app-beta.iq -y …` (see Multi-channel builds below).

The compiler builds every product in the manifest, so a device that fails to build (missing capability, over the 128 KB budget on that tier) fails the whole export. Vet the full product list (Workflow B) before the first release, not just your dev device — building a per-device `.prg` for each product (`monkeyc -d <device> …` in a loop) surfaces a per-tier failure faster than waiting for the `-e` export to choke on it.

## Key and app-id continuity

Two identifiers must stay constant for the life of a published app:

- **App id** (the UUID in `manifest.xml`) — the store identity. The scaffold generates one; freeze it. A new id is a brand-new app, not an update.
- **Developer key** — the `.der` that signs the `.iq`. The store ties the app to the key that first uploaded it; signing an update with a different key is rejected. This is why [toolchain.md](toolchain.md) insists on generating the key once and never overwriting it — losing it strands the published app with no way to ship updates. Back up the `.der` (and `.pem`) somewhere durable.

## Store listing and supported devices

The listing (name, description, icon, screenshots, category, pricing) is entered in the Connect IQ developer dashboard, not the manifest. The **supported-device list is derived from the manifest products** — only listed devices can install it. Adding a device after launch means a manifest change, a rebuild, and a new release.

The launcher icon shipped in the `.iq` is what the store and the device launcher show; replace the scaffold's generated placeholder before release.

For a **data-driven face**, store screenshots are a problem: in the sim the face may render empty (no synced sensor data, no successful background fetch yet), so a naive capture shows a blank dial. Bake in a **sample-data path**: a frozen representative payload in the view plus a hidden boolean property (e.g. `SampleData`, default false, *not* exposed in the settings UI) that makes the view draw the sample instead of live/stored data. Enable it only for the capture run (the env-var override mechanism in [settings.md](settings.md) flips it for one build), and the gallery comes out deterministic regardless of sim state. Refresh the frozen snapshot periodically so it stays representative.

## Versioning and updates

Each store upload needs a version higher than the last (set at upload time in the dashboard). An update is: bump the version, re-export the `.iq` **with the same key and app id**, upload. Users get it on their next sync. App settings persisted on-device survive updates, so honour old stored values (see the migration note in [settings.md](settings.md)) rather than assuming a clean slate.

## Multi-channel builds (dev / beta / production)

A face that ships to users wants three identities that **coexist on one watch** for testing without colliding. The app id is the on-device identity, so each channel needs its own id — but they share all the code. The concrete structure that scales:

- Three manifests — `manifest.xml` (production, the permanent public id), `manifest-beta.xml` (beta-channel id, name "App Beta"), `manifest-dev.xml` (local-sideload id, name "App Dev") — differing only in `id` and `name`.
- Three jungles — `app.jungle`, `app-beta.jungle`, `app-dev.jungle` — each just sets `project.manifest = manifest-<channel>.xml` and otherwise **shares the same `base.sourcePath = source` and `base.resourcePath = resources`**. One source tree, one resource tree, three identities.

```
# app-dev.jungle
project.manifest = manifest-dev.xml
base.sourcePath = source
base.resourcePath = resources
```

Then: `monkeyc -f app-dev.jungle …` for the sideload build (install.sh), `-f app-beta.jungle -e -r` for the beta `.iq`, `-f app.jungle -e -r` for the production `.iq`. The dev and beta ids stay constant and separate from production forever, so all three can be installed at once and none can ever be mistaken for a production update.

**Keep non-production jungles out of the project root.** The bundled scripts (simrun.sh, shot.sh, auto-shot.sh, install.sh, uninstall.sh) auto-detect the jungle with `ls ./*.jungle | head -1`, so two jungles in the root makes them pick the alphabetically-first one — `app-beta.jungle` shadows `app.jungle`, and an override run silently builds the wrong channel. Put the extra jungles under a `channels/` subdirectory (`channels/app-beta.jungle`, `channels/app-dev.jungle`) so only the production `app.jungle` sits in root; pass the channel jungles explicitly with `-f` (the Makefile's `package-beta` target does this). The scripts then always resolve to production.

The store also has its own **beta-test track** (upload a build visible only to invited testers under the *production* app id) — that is for pre-release testing of the real app, orthogonal to the separate-id dev/beta builds above, which exist so you can run a work-in-progress next to the installed store copy.

## Review and common rejections

Garmin reviews submissions before they go public. Recurring rejection causes worth pre-empting:

- A product in the manifest the face does not actually render correctly (build succeeds but layout is broken on that screen) — review tests across the listed devices.
- Placeholder or low-resolution store assets / launcher icon.
- Requesting permissions the face does not use (see [data-sources.md](data-sources.md)); ask only for what you read.
- Crashes or a blank face on first launch before settings are configured — ship working code defaults so the face renders with no Garmin Connect configuration.
