# Fonts and text sizing

## Contents
- The problem: bitmap font sizes vary by device
- The solution: size off the dial radius, render via vector
- System fonts: pick by measured width, never upsize
- Vector vs bitmap fallback
- Other divergence sources
- Checklist

## The problem: bitmap font sizes vary by device

The CIQ system bitmap fonts (`FONT_XTINY`, `FONT_TINY`, …) are defined per device in firmware at device-chosen pixel sizes that are **not** proportional to the screen. So `getFontHeight(FONT_XTINY)` returns a different height on each device, and a layout tuned on one device renders out of proportion on another. Devices also use different font *technologies*: some ship pre-rasterized **bitmap** fonts, others ship **scalable TTF** system fonts rasterized at runtime.

Worked example: one device renders XTINY at 29 px on a 390-px screen; another renders it at 34 px on a 416-px screen. The font is +17% while the screen is only +7% larger, so a layout keyed off `getFontHeight` blows up on the second device.

## The solution: size off the dial radius, render via vector

Pick a **reference device** (the one you tune on) and record its dial radius and the font heights you want at that radius. Then size all text proportionally to the actual dial radius and render with vector fonts:

```
scale = radius / REF_RADIUS
xtinySize = REF_XTINY * scale
tinySize  = REF_TINY  * scale
```

Build the vector fonts at those sizes (e.g. via `getVectorFont(:size)`). Text then keeps the reference proportions on every device regardless of that device's bitmap font sizes. Measure layout offsets off the **resolved** font (`getFontHeight` of whatever font you actually draw with), so nudges track the rendered glyphs whether vector or bitmap-fallback.

Example reference constants from an analog face tuned on a 390-px device: `REF_RADIUS = 195`, `REF_XTINY = 29`, `REF_TINY = 39`. Use your own from your reference device.

## System fonts: pick by measured width, never upsize

For a value drawn with a **system font** (e.g. the clock in `FONT_NUMBER_MEDIUM`), you cannot size proportionally — you get the device's fixed font tiers, and those tiers differ across devices (a fenix renders the number font larger than a venu/marq at the same resolution), so a tier that fits on your reference device overflows on another. Don't hardcode the tier. Measure and step down:

```
font = FONT_NUMBER_MEDIUM
if (dc.getTextWidthInPixels(str, font) > w * 0.43) { font = FONT_NUMBER_MILD }
```

Pick the largest tier that fits your width budget and fall back to a smaller one when it doesn't — **never upsize** (the reference tier is the ceiling). `getTextWidthInPixels` reflects the actual device font, so this adapts per device with no per-device constants. (For your own text where a vector font is available, size off the dial radius instead, as above.)

## Vector vs bitmap fallback

- Straight values: prefer a vector font for consistency, but you can **fall back to the bitmap font** where no scalable face exists. Keep layout offsets on the resolved font so the fallback still lines up.
- Curved / radial text (`drawRadialText`): requires a `VectorFont`. There is **no bitmap fallback** — if `getVectorFont` returns null the field silently vanishes. Vet every target for vector fonts before relying on radial text (see [device-capabilities.md](device-capabilities.md)).
- Provide a **faces fallback list** when requesting a vector face (e.g. a preferred condensed bold, then plainer faces, down to a face you know a minimal device has like `RobotoRegular`). Different devices expose different named faces.

## Other divergence sources

- The simulator's bundled font metrics can differ from device firmware (Garmin's changelog repeatedly "fixes sim font sizes to match devices"). Verify on hardware.
- Switching device in a running sim renders stale fonts — restart the sim.
- `DeviceSettings.fontScale` and enhanced-readability mode scale system text on-device; the sim defaults to 1.0.
- `getVectorFont(:size)` glyph height is not guaranteed exactly equal to the requested px (face/device specific). If a device is off, add a per-face size offset; keeping layout on the resolved font height absorbs the rest.

## Checklist

```
- [ ] Reference device chosen; REF_RADIUS / REF_<size> recorded from its measured heights
- [ ] All text sized as REF_<size> * radius / REF_RADIUS
- [ ] Layout offsets measured off the resolved (drawn) font, not FONT_<size>
- [ ] Vector face requested with a fallback list
- [ ] Every target vetted for vector fonts if radial/curved text is used
```
