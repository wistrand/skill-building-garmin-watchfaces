# Device capabilities: what to vet and why

## Contents
- Why vet before designing
- Where the data lives
- The capabilities that decide a design
- Vector fonts: the most common late surprise
- Using vet-device.py

## Why vet before designing

Devices differ in ways that silently break a face: a missing font technology drops text, a small graphics pool refuses your cached buffers, an older API level rejects a call. The cheapest time to find this is before writing drawing code. Let the weakest target set the design ceiling.

## Where the data lives

Each downloaded device has two descriptors under `~/.Garmin/ConnectIQ/Devices/<id>/`:

- `compiler.json` — display type, resolution, colour depth, graphics support flags, API levels (`partNumbers[].connectIQVersion`), alpha blending.
- `simulator.json` — `graphicsResourcePoolSize`, the font table, layouts, capacities.

`vet-device.py` reads both and prints a verdict. The raw fields are worth knowing so you can confirm anything by hand.

## The capabilities that decide a design

| Field (file) | What it gates |
|---|---|
| `displayType` (compiler) | `amoled` → burn-in rules and always-on dimming apply ([aod-and-sleep.md](aod-and-sleep.md)). Memory-in-pixel (MIP) devices behave differently in low power (per-second partial updates). |
| `partNumbers[].connectIQVersion` (compiler) | API level. Must be ≥ your manifest `minApiLevel`. Newer APIs (graphics pool, vector fonts, complications) require a high enough level. |
| `resolution` (compiler) | Screen size and shape. Layout and font sizing should scale to the dial radius, not be hardcoded ([fonts.md](fonts.md)). |
| `bitsPerPixel` (compiler) | Colour depth. 16-bit full colour supports anti-aliased non-palette buffers; low-depth/palette devices cannot anti-alias paletted buffers. |
| `enhancedGraphicSupport` (compiler) | CIQ 4 graphics pool. Required for `createBufferedBitmap` caching and image baking. |
| `graphicsResourcePoolSize` (simulator) | The pool size in bytes (commonly 3–4 MB). Your cached/baked buffers must fit here, not on the 128 KB heap ([performance.md](performance.md)). |
| `alphaBlendingSupport` (compiler) | Whether alpha blends work. Note direct-to-Dc `setColor` ignores alpha; alpha needs `setStroke`/`setFill` (32-bit AARRGGBB). |
| system **vector (TTF) fonts** (simulator font table) | Whether `getVectorFont` returns usable faces. See below. |

## Vector fonts: the most common late surprise

Curved/radial text (`drawRadialText`) and proportional vector sizing both need a system `VectorFont` from `getVectorFont`. Some devices ship only **bitmap** system fonts and no scalable faces. On those, `getVectorFont` returns null and any radial/curved field **silently vanishes** — there is no bitmap fallback for `drawRadialText`. (Cardinal/straight values can fall back to a bitmap font; curved text cannot.)

How to tell from the descriptor: in `simulator.json`, the `ww` font set lists each font. Scalable devices have entries with `"type": "ttf"` and named faces (e.g. `RobotoRegular`, `YantramanavRegular`). Bitmap-only devices have entries like `{"filename": "FNT_..._TINY", "name": "xtiny"}` with no `type` and no named scalable faces. The presence of any TTF entry is the signal that `getVectorFont` will work.

This is exactly why some otherwise-capable AMOLED devices get dropped from a radial-text design: newer or AMOLED does not imply scalable fonts. Always check.

## Using vet-device.py

```bash
# download first (descriptors + fonts)
connect-iq-sdk-manager-cli device download -d venu2 --include-fonts

# report all capabilities
scripts/vet-device.py venu2

# assert hard requirements; non-zero exit if any are missing
scripts/vet-device.py venu2 --need vector-fonts graphics-pool

# compare several targets at once
scripts/vet-device.py marq2 fenix843mm venu3 venu2
```

The `--need` capabilities are: `amoled`, `vector-fonts`, `graphics-pool`, `alpha`, and `api>=X.Y.Z`. Use them in CI or a pre-commit check so adding an unsupported target fails loudly.
