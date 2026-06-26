# Always-on (AOD) and sleep

## Contents
- The callback contract
- AOD on vs off: same callbacks, different meaning
- Burn-in rules (AMOLED)
- There is no API to query power mode
- Dropped callbacks and how they strand the face
- Cadence-based recovery (two-path pattern)
- Deferring heavy work off the wake frame

## The callback contract

A watch face is a `WatchUi.WatchFace` and receives exactly two power-state callbacks:

- `onExitSleep()` — entering high power (gesture wake, return from an app/notification). Per-second `onUpdate` follows for a short window.
- `onEnterSleep()` — entering low power. `onUpdate` is then called about once per minute (plus `onPartialUpdate` per second on MIP devices, not AMOLED).

The canonical pattern is a single boolean toggled in those callbacks, with `onUpdate` branching on it:

```
function onExitSleep()  { _sleeping = false; WatchUi.requestUpdate(); }
function onEnterSleep() { _sleeping = true;  WatchUi.requestUpdate(); }
function onUpdate(dc)   { ... if (!_sleeping) { drawSecondHand(); ... } }
```

Gate every always-on-dropped element (second hand, fine animation, heavy fills, large bright areas) on that flag.

## AOD on vs off: same callbacks, different meaning

The face is not told whether the user enabled Always On. It only ever sees high vs low power. The user's setting changes what low power physically means:

- **AOD enabled**: low power is the dimmed always-on screen. The once-a-minute `onUpdate` is rendered and visible, and must obey burn-in rules.
- **AOD disabled**: low power is the screen fully off. The same low-power branch runs but is never seen; a gesture wake produces `onExitSleep` and a brief full-brightness burst.

Design for "high vs low power", not for the user's setting. There is no API to read the Always On toggle.

## Burn-in rules (AMOLED)

When `displayType` is `amoled`, the device reports `requiresBurnInProtection` in `DeviceSettings`. In low power you must keep bright pixels sparse (commonly cited as roughly ≤10% of pixels lit and no static pixel held too long); the OS also dims and pixel-shifts. Keep colours but drop or thin large/bright elements when sleeping. `requiresBurnInProtection` tells you how to draw the low-power view; it does **not** tell you the current power state.

## There is no API to query power mode

The only signal is the two callbacks. No API reports the watch face's current power state — you cannot poll "am I awake?" (the `Activity.Info.isSleepMode`/`UserProfile` sleep fields are about the *user's* night-sleep schedule, not the face's low/high power). If a callback is dropped, nothing in the official API lets you recover deterministically.

## Dropped callbacks and how they strand the face

On real firmware the callbacks are not perfectly reliable:

- A dropped `onExitSleep` on a gesture wake leaves the face in the low-power draw at full brightness (the classic "low-power styling while bright" bug).
- A dropped `onEnterSleep` (e.g. after a notification steals and returns focus) leaves the face drawing the awake view in low power.

Because the query API is gone, the only recovery is to infer power mode from the `onUpdate` stream.

## Cadence-based recovery (two-path pattern)

Infer the real mode from update frequency. A genuinely awake watch delivers a continuous ~1 Hz stream; low power delivers only a short burst (about 1.5 s of a few updates) roughly once a minute. A frame *count* is fooled every minute, so key on the **duration** of the run of consecutive fast updates.

Two paths cover the two cases:

- **Slow path (always-on / AOD wake).** Track the start of the current run of fast (<30 s apart) updates. If that run lasts several seconds (e.g. ≥5 s) while still flagged asleep, treat the system as awake and clear the flag. The threshold sits above the ~1.5 s low-power burst so a burst cannot trip it. Reset the run in `onEnterSleep` so the post-sleep burst cannot re-wake.

- **Fast path (non-AOD gesture wake).** With Always On off, the screen is dark while asleep, so **no** `onUpdate` fires until the wake. The slow path cannot catch this because a non-AOD wake is only a few seconds (shorter than the 5 s threshold) and the run resets at every wake. So treat a fast frame that follows a long silence (a gap well above the ~60 s low-power burst cycle, e.g. ≥90 s) as a real wake and clear the flag on the **first** frame.

Make the fast-path wake **tentative**: a genuine wake keeps streaming, whereas an anomalous low-power gap would die like a burst. If the stream breaks (another long gap) before lasting a short confirm window (e.g. 2.5 s, longer than a burst but shorter than a real wake), revert to asleep. That bounds a misfire to one burst instead of a permanent stuck-awake. A stream that outlasts the confirm window is locked in. Clear the tentative flag in both `onEnterSleep` and `onExitSleep`, since a real callback is authoritative.

Caveat: the fast path assumes real non-AOD sleep is **silent**. Some simulators emit phantom once-a-minute bursts even with AOD off, in which case the fast path will not trigger in the sim; verify it on a device. If a device's low power delivers a continuous 1 Hz stream (seen on some firmware), no cadence heuristic can distinguish it from awake — that case is out of reach for any of this, including the slow path.

## Deferring heavy work off the wake frame

Unlike the sim, the device enforces a per-`onUpdate` execution budget. The first frame after a wake (especially a cold start) is the worst place for a heavy one-off such as baking an image buffer: overrunning the budget can throttle the device back to low power, which looks like the face being "stuck" asleep just after install.

Defer it: on the wake frame, draw the existing (possibly stale) buffer or nothing, call `requestUpdate`, and do the heavy work on the next frame. Keep independently-keyed buffers so you can defer one heavy op at a time rather than rebuilding everything on the worst frame.
