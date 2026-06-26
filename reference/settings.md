# App settings and configuration

## Contents
- Where settings live
- The value convention
- Reading settings in code
- Configuring on device vs in the sim
- The simulator gotchas
- Overriding settings for a build (offline)
- Generating settings docs

## Where settings live

Configurable options for a watch face go in `resources/settings/`:

- `settings.xml` — one `<setting>` per option, referencing a property and a strings label. Each `<setting>` can carry a `prompt="@Strings.…"` description, which Garmin Connect shows as help text. (Custom attributes are schema-rejected; `prompt` is the only extra metadata hook.)
- `properties.xml` — the property ids and their **default** values.

Keep settings in exactly one place. The resource compiler compiles every `*.xml` under the resource path recursively and tolerates duplicate `<setting>`s, so a stray second settings file silently double-compiles and only surfaces as a dangling reference error when the two drift. If a settings/strings reference fails to resolve in a file you did not edit, search the resource tree for a duplicate.

Two compile-time gotchas in these files:

- **`<settingConfig type="list">` entries must be numeric.** Each `listEntry value` is coerced to the linked property's type, so string values fail with `Unable to process 'setting' resources: For input string: "<value>"`. Use a **number** property with numeric `value`s and map the index → label in code (this is also why the `-1`/`-2` convention below is numeric). Put the human label in the `listEntry` text via `@Strings.…`, not in the value.
- **The root element needs the schema declaration**, or the compiler rejects the file: `xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="https://developer.garmin.com/downloads/connect-iq/resources.xsd"` on the `<properties>`/`<settings>` root.

## The value convention

A clean, uniform convention across every setting makes each field nullable from Garmin Connect and keeps the code simple:

- `-1` = Default (use the code default for this option)
- `-2` = None / Off (hide or disable this element)
- other values = a specific choice (an enum index, a type code, a colour, a free value)

So "hidden" and "use default" are distinct and uniform: a colour set to `-2` means hide the element, `-1` means the built-in default colour, any other value is the chosen colour. Apply the same `-1`/`-2` meaning everywhere (toggles, colours, complication slots, timezone, …) so there is one rule to remember.

## Reading settings in code

Read `Application.Properties` in an `applyProperties()` method, call it at init, and re-apply on sync via `AppBase.onSettingsChanged()`. Treat a legacy `0` as default if you migrated from an older scheme.

## Configuring on device vs in the sim

- **On device (beta or store install)**: the user edits settings in **Garmin Connect**; the watch syncs them. This is the real pipeline.
- **Native on-watch editor**: a watch-face complication editor exists but cannot represent some composite defaults (it only speaks "a type" or "cleared"). If your defaults are richer than that, prefer Garmin-Connect-only configuration and skip the native editor rather than maintaining two config surfaces with precedence rules.

## The simulator gotchas

These cost hours if you do not know them:

- `monkeydo` / a plain load sends only the `.prg`, so the sim's **App Settings Editor stays empty** ("No settings file found") even though the build emits a valid settings JSON. That editor is a web view that POSTs the descriptor to a Garmin web service and renders the returned form, so it needs **both** the descriptor pushed by the VS Code Monkey C extension (Build + Run) **and** internet access. There is no purely-local settings form.
- To test settings fully offline, change a default in `properties.xml` and confirm `applyProperties()` applies it.
- When you change a default, first **delete the sim's persisted store** for the app before relaunching. The sim keeps the previously-seeded value, and a new `properties.xml` default never overwrites an already-stored property. A stale stored value can mask a new default and look like a bug when the on-device behaviour is fine. The store is `/tmp/com.garmin.connectiq/GARMIN/APPS/SETTINGS/<APP-NAME>-<DEVICE>.SET`, named after the manifest **display name** uppercased (spaces → hyphens), *not* the jungle or `.prg` basename — e.g. an app named "AI Status" on marq2 is `AI-STATUS-MARQ2.SET`. To clear it without guessing the app name, match on the device: `rm -f /tmp/com.garmin.connectiq/GARMIN/APPS/SETTINGS/*-MARQ2.SET`.

## Overriding settings for a build (offline)

Since the sim's settings form needs the VS Code extension + internet, the offline way to exercise a non-default setting is to **bake it into the build**: patch the `<property>` default in `properties.xml`, build, then restore the file. `scripts/simrun.sh` automates this — pass overrides as env vars named exactly after the property ids, and it also restarts the sim with the persisted `.SET` cleared so the new default actually takes:

```bash
accentColor=0xFF3030 showDate=true scripts/simrun.sh fenix843mm     # in the sim
accentColor=0xFF3030 scripts/simrun.sh --install fenix843mm         # sideloaded to a watch
```

A sideloaded (non-Connect) build reads its settings only from the baked `.prg` defaults, so this is also how you pin settings on a sideload.

## Generating settings docs

Because each `<setting>` carries a `prompt` and a label, a small stdlib-only script can resolve the `@Strings`/`@Properties` references and emit a Markdown reference of every option. `scripts/gen-settings-doc.py` does this (run from the project dir; writes `docs/settings.md` by default). Worth doing for a face with many settings, so the docs never drift from the resources.
