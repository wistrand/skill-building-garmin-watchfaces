# Background services and web data

A watch face cannot fetch in the foreground — `makeWebRequest` is not available from `onUpdate`. Network data comes from a **background service**: a separate process, on a temporal trigger, that fetches and hands the result back to the face through storage. This is the least forgiving part of a face; the constraints below each cost hours if discovered late.

## Contents
- The shape of it
- makeWebRequest: real HTTPS, no redirects
- The background memory budget and -403
- `(:background)`: the right tool, easy to misaim
- Handing data back: Storage + instanceof
- Triggering and watching it in the sim

## The shape of it

```
App.getServiceDelegate()  -> returns your ServiceDelegate (a Toybox.System.ServiceDelegate)
App.onStart / a temporal event registration  -> Background.registerForTemporalEvent(Time.Duration)
ServiceDelegate.onTemporalEvent()  -> one makeWebRequest, then Background.exit(result)
App.onBackgroundData(data)  -> store the payload in Application.Storage
View.onUpdate()  -> read the stored payload, draw
```

Permissions: `Communications` (the HTTPS request) and `Background` (the temporal event). Both must be in the manifest; without them the calls fail silently (see [data-sources.md](data-sources.md)).

The temporal event has a **5-minute platform minimum** — you cannot poll faster. Do as little as possible in the service: one request, no per-item fan-out, no heavy parsing. Push aggregation/normalization to a server you control and keep the device side dumb.

## makeWebRequest: real HTTPS, no redirects

- It requires **public, CA-trusted HTTPS** on a real device. `http://localhost` works only in the simulator (it shares the host network); self-signed certificates fail on hardware. So a build that fetches fine in the sim against a local server gets nothing on the watch — point the device at the deployed public URL.
- It does **not handle redirects reliably**. Depending on firmware you get the 3xx back with `data` null, or a silent retry at the `Location` that drops the POST body (so the new host 411s), or `responseCode 0`. Treat any redirect as a failure and point at the **final** host — a URL that starts 302-ing (a provider moving hosts, a trailing-slash redirect) silently breaks a previously-working fetch.

## The background memory budget and -403

The background process gets **far less memory than the foreground app** — often only ~32 KB of combined code and data (e.g. a fenix 6X Pro reports 32 KB for the background process vs 128 KB for the foreground). A response that is too large to allocate/parse there fails with `onReceive(responseCode = -403, …)` = `NETWORK_RESPONSE_OUT_OF_MEMORY`: the HTTP request *succeeded*, the JSON just could not be held. It looks like a network failure but is a memory failure. Note that parsing JSON into a Monkey C `Dictionary` costs **well over twice** the raw byte size, so the budget is tighter than the payload size suggests.

The fix is to shrink the payload, not to retry:

- Return only what the face draws, in the most compact encoding that still parses. A real case cut an 11-item payload ~4× (≈4.9 KB → ≈1.2 KB) and that alone cleared the -403, by shipping a per-bucket **severity-digit string** (`"0002030…"`) instead of arrays of `[severity, height]` pairs — the height is re-derived on the device.
- Prefer short keys, scalars over objects, and derived values computed client-side from one number.
- Request `Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON` so the platform parses it; a giant string you parse yourself is worse.

## `(:background)`: the right tool, easy to misaim

The `(:background)` annotation, paired with `excludeAnnotations` in the jungle (`<device>.excludeAnnotations = …`), is the standard way to fit the background process in its ~32 KB budget: mark the background-only code `(:background)` and exclude the heavy foreground-only code from the background build so the service loads only what it needs. Reach for it when you hit `-403`.

The trap is *what* you annotate, not the annotation itself. The compiler warns that `getServiceDelegate()` is "implicitly added to the background" and invites you to annotate it `(:background)` to silence the warning — don't do that reflexively. `getServiceDelegate()` is the foreground app's hand-off *into* the background; at least one real project found that annotating it made the temporal event **silently stop firing**, with no error. The warning is benign on a small face: leave the app entry points and `getServiceDelegate()` un-annotated, and scope `(:background)` to the genuinely background-only code instead.

## Handing data back: Storage + instanceof

`Background.exit(payload)` delivers to `App.onBackgroundData(data)`, which writes to `Application.Storage`; the view reads it in `onUpdate`. Two rules:

- The face renders whatever was last stored, which may be **from an older build with a different shape** (Storage survives updates). Guard every read with `instanceof` (`data instanceof Dictionary`, then `providers instanceof Array`), not a cast — a Monkey C cast does not convert, it asserts, and crashes on first use of the mis-shaped value.
- Treat "no data yet" as a first-class state: before the first successful fetch the store is empty, so draw a sensible placeholder rather than assuming a payload.

## Triggering and watching it in the sim

The simulator does **not** fire temporal events on a wall clock. Trigger one by hand: **Simulation → Trigger Background Events → Temporal Event**. It is throttled to once per 5 minutes; a sim restart resets the throttle. A face stuck on a stale "updated N min ago" almost always means no successful fetch on the current build — trigger the event, and if it still fails check the device path (not localhost) and the response code.

To see what happened, add temporary `System.println` in `onTemporalEvent` / `onReceive` / `onBackgroundData` to log the HTTP code and whether data was stored. Background logs land in `/tmp/ciqsim.log` (and `/tmp/monkeydo.log`) when the sim is launched headless by the scripts — there is no GUI console for the background process. Remove the tracing afterwards.
