# Performance and memory

## Contents
- Two budgets: the 128 KB heap and the graphics pool
- The per-frame cost model
- What is expensive
- Caching into a pool buffer
- Precompute constant geometry
- Profiling
- Drawing gotchas

## Two budgets: the 128 KB heap and the graphics pool

A watch face is capped at **128 KB** of heap. This is a fixed app-*type* policy, not a per-device figure: flagship and entry devices both report `watchFace = 131072` in `compiler.json`. The same hardware allows far more for a watch *app* (e.g. 768 KB), but a watch app is a different, non-always-on product. So you do not get more face memory by targeting a newer watch.

`BufferedBitmap`s do **not** live on that heap. With `enhancedGraphicSupport` (CIQ 4) there is a separate **graphics pool** (commonly 3 MB, 4 MB on some devices; `graphicsResourcePoolSize` in `simulator.json`). `createBufferedBitmap` allocates there. This is the key to caching: a full-screen cache that would never fit in 128 KB fits comfortably in the pool. Size memory decisions against the right budget — several "can't cache" conclusions are just the wrong budget being measured.

Pool buffers can be **purged** under pressure. Always guard `ref.get()` for null and re-render when it returns null.

## The per-frame cost model

The face is fully re-rendered every `onUpdate`. A second hand forces a full redraw each second, and a full-screen persistent cache that swallows the `clear` is usually impractical at 128 KB. So per-frame cost is what matters, and the simulator hides it (no execution budget). Profile and reason about the device.

## What is expensive

Rough ordering from profiling an AMOLED analog face (your numbers will differ, but the ratios hold):

- **Curved/radial vector text** is by far the heaviest: on the order of ~7 ms per label for per-glyph anti-aliased rasterization. Four labels can dominate a frame.
- **`drawArc`** is moderately expensive and roughly **10x** the cost of `drawLine` (e.g. ~250 µs vs ~24 µs). Many small arcs (gradient rings, sun rings) add up.
- **`clear`** is a few milliseconds for a full-screen wipe, unavoidable without partial updates.
- **`fillCircle` / `drawText` (straight)** are cheap by comparison.
- A **pre-baked image blit** (`drawBitmap`) is about 1 ms regardless of how expensive the bake was.

## Caching into a pool buffer

The highest-leverage optimization: render anything that changes rarely into a transparent dial-sized `createBufferedBitmap` once, then blit it each frame with a single `drawBitmap`. Re-render only when its inputs change.

- Use a **cache key** of the inputs (the field strings, the sleep flag, any colour/setting that affects it). Rebuild when the key changes — often about once a minute, plus on a sleep transition.
- Bake awake-only elements into the buffer and drop them when the key says asleep.
- Full-colour (non-palette) pool buffers **can** anti-alias. The anti-aliasing restriction applies only to *paletted* buffers. Transparent (`ALPHA_BLENDING_FULL`) pool buffers composite correctly on current SDKs.
- Guard `get()` for null (purge) and re-render, exactly as the cache build path does.

For the wake frame specifically, see the deferral note in [aod-and-sleep.md](aod-and-sleep.md): keep buffers independently keyed so a heavy rebuild does not have to share the wake frame with an image bake.

## Precompute constant geometry

Hoist per-frame trigonometry that never changes. Tick positions around a ring, a parametric curve (e.g. a heart), gradient-arc step angles and colours: compute the `sin`/`cos` once at init into arrays and index them each frame. This removes hundreds of trig calls per awake second and is pixel-identical. Deduplicate hand-angle trig too (compute `sin`/`cos` once per hand).

## Profiling

The SDK profiler reports cumulative Call Count over the captured frames (divide by the frame count for per-frame), and you want **Actual (self/exclusive) Time**, not Total. Native operations like curved text show up as `<Native Code>` rather than a named `Dc.` row. `System.println` lands in `/tmp/monkeydo.log`; never leave a per-frame `println` that does real work in `onUpdate`.

## Drawing gotchas

- `fillPolygon` fills only with **integer** points; float points render edges only. Round before filling.
- Direct-to-Dc `setColor` ignores alpha, and the sim ignores blend modes. Alpha-blended lines/fills need `setStroke`/`setFill` with 32-bit AARRGGBB; a later `setColor` re-takes precedence.
- Paletted `BufferedBitmap`s cannot anti-alias, and a full-colour-to-palette quantize blit is rejected. With a graphics pool there is no reason to use palette buffers for caching.
