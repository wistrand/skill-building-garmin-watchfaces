# Data sources and permissions

## Contents
- The watch-face execution context
- Permissions: declare what you read, or get nothing
- Where each value comes from
- Location: a fallback chain, guarding null *and* out-of-range
- Everything is nullable
- Web data needs a background service
- Simulator: inject the inputs

## The watch-face execution context

A watch face is not a full app. It runs in a constrained, always-on context with the 128 KB budget ([performance.md](performance.md)) and **no continuous sensor streaming** — you read snapshots in `onUpdate`, you do not subscribe to a live feed. Anything power-hungry (continuous GPS, an active ANT+ sensor session) is for a device app, not a face. Design around periodically-sampled values that the system already maintains.

## Permissions: declare what you read, or get nothing

Each restricted API requires a matching entry in the manifest:

```xml
<iq:permissions>
    <iq:uses-permission id="UserProfile"/>
    <iq:uses-permission id="Positioning"/>
    <iq:uses-permission id="SensorHistory"/>
</iq:permissions>
```

The scaffold ships `<iq:permissions/>` **empty**. Call a gated API without its permission and you do not get an obvious error at the call site — you get a `PermissionRequiredException` (or simply unavailable data), which reads as a mysterious blank field. Add the permission when you add the data source.

Ask for **only** what you use: unused permissions are a common store-review rejection ([publishing.md](publishing.md)) and show up on the store listing.

## Where each value comes from

| Data | Source | Permission |
|---|---|---|
| Time / date | `System.getClockTime()`, `Time.Gregorian` | none |
| Battery, charging | `System.getSystemStats()` | none |
| Steps, floors, calories, move bar, daily/current HR | `ActivityMonitor.getInfo()` | none |
| Current heart rate (ambient) | `Activity.getActivityInfo().currentHeartRate` | none |
| HR / pressure history (graphs) | `Toybox.SensorHistory` | `SensorHistory` |
| Resting HR, HR zones, age/weight, sleep/body-battery (where exposed) | `UserProfile` | `UserProfile` |
| Weather (current conditions, forecast) | `Toybox.Weather` (CIQ 3.2.0+) | none, but device must support it and have synced data |
| Location (for sunrise/sunset, etc.) | `Position.getInfo()` (last known) or `Activity.Info.currentLocation` | `Positioning` |
| Device settings (12/24h, units, DND, notifications, `fontScale`) | `System.getDeviceSettings()` | none |

`Weather` and `SensorHistory` exist only from the API levels that introduced them — gate on your `minApiLevel` and vet targets ([device-capabilities.md](device-capabilities.md)). `Position.getInfo()` returns the **last known** fix; a face does not get a live GPS lock, so location can be stale or absent indoors.

## Location: a fallback chain, guarding null *and* out-of-range

`Position.getInfo()` in a face returns the **last known** fix, which can be missing (indoors, no recent GPS) — but worse, the **simulator resets GPS to a non-null garbage value (lat/lon ≈ 180°) after a restart**, which is in-range-looking enough to sail past a null check and produce nonsense (wrong sunrise/sunset, a moon tilted at impossible angles) with no code change. A real watch never reports invalid coordinates; the sim does, routinely.

So resolve location as an explicit fallback chain, and at **each** step reject both null and out-of-range (`|lat| > 90.5°`, `|lon| > 180.5°`), not just null:

1. GPS (`Position.getInfo()`) — if usable.
2. Weather observation location (`Weather.getCurrentConditions().observationLocationName`/position) — often present when GPS is not.
3. A fixed default — only as a last resort.

Two refinements that matter:

- **Don't let a garbage fix skip the fallback.** A GPS-first resolver that only falls through when GPS is `null` will *take* the sim's `(180,180)`, then trip the range guard later in isolation — leaving other location consumers (e.g. a weather-derived sun ring) pointing somewhere else. Apply the same usable-or-skip test at the GPS step so a garbage fix falls through to weather, keeping every consumer on one location.
- **Distinguish "sim garbage" from "genuinely no location."** Funnelling both to the fixed default means a real watch with no GPS *and* no weather draws a fake location instead of a neutral view. Prefer: out-of-range (sim) → default (sim convenience); truly null → null → draw the neutral/location-independent variant.

## Everything is nullable

Every field above can be null or sentinel: no HR strap → `currentHeartRate` null; indoors → no location; weather not yet synced → null conditions; `ActivityMonitor` fields null early after boot. Null-check every read and draw a sensible fallback. A face that assumes a value is present is the classic "works for me, blank for them" report.

## Web data needs a background service

A watch face cannot make a web request from `onUpdate`. If you need network data, a background service fetches it on a temporal trigger (5-minute minimum) and hands it back through storage. For most faces, prefer the data Garmin already syncs (`Weather`, `ActivityMonitor`) over rolling your own fetch — the background path has sharp, non-obvious constraints (a tiny memory budget, HTTPS/redirect rules, an annotation that silently kills it). All of it is in [background-services.md](background-services.md).

## Simulator: inject the inputs

The sim reads nothing real. Set values from the **Simulation** menu (heart rate via Health, weather/GPS via the Simulation menu) or fields come back unavailable — see [toolchain.md](toolchain.md). Because the sim hands you clean data, it is the wrong place to confirm null-handling; verify the empty cases (no strap, no GPS, no synced weather) on hardware.
