## 2.2.2

- 📝 **Docs**: improved the documentation.

## 2.2.0

- ✨ **New feature**: added the Sierra family of error-diffusion kernels (Frankie Sierra):
    - `DitherKernel.sierra3` — Sierra / Sierra-3, 10 neighbours, divisor 32.
    - `DitherKernel.sierra2` — Two-Row Sierra / Sierra-2, 7 neighbours, divisor 16.
    - `DitherKernel.sierraLite` — Sierra Lite / Sierra-2-4A, 3 neighbours, divisor 4.

## 2.1.0

- 💥 **Breaking change**: renamed the ordered-dither `strength` parameter back to
  `intensity` for a more fitting, consistent name across the dithering API:
    - `EInkImageProcessor.strength` → `intensity`
    - `ditherImage`, `ditherImageOrdered`, `ditherImageBayer`, `ditherImageBlueNoise`
      parameter `strength` → `intensity`
    - Update call sites, e.g. `EInkImageProcessor(intensity: 1.0)` and
      `ditherImage(image, intensity: 1.0)`.
- ✨ **New feature**: added a `patternSize` parameter ("Pattern Size") to control the
  scale of the dither pattern, similar to the control in many halftone editors:
    - `EInkImageProcessor.patternSize`
    - `ditherImage`, `ditherImageOrdered`, `ditherImageBayer`, `ditherImageBlueNoise`
      parameter `patternSize` (default `1`)
    - For **ordered kernels** (Bayer / blue noise) each threshold-matrix cell now covers
      `patternSize`×`patternSize` pixels instead of 1×1, stretching the pattern to be
      coarser / larger.
    - For **error-diffusion kernels** (Floyd–Steinberg, Stucki, etc.) the diffusion now
      runs on a `patternSize`×`patternSize`-block downsampled grid and each block is
      expanded back, so the dither "dots" grow with `patternSize`.

## 2.0.0

- 💥 **Breaking change**: renamed the ordered-dither strength parameter for a consistent
  naming convention across the dithering API:
    - `EInkImageProcessor.intensity` → `strength`
    - `ditherImage` parameter `bayerStrength` → `strength`
    - Update call sites, e.g. `EInkImageProcessor(strength: 1.0)` and
      `ditherImage(image, strength: 1.0)`.
- 💥 **Breaking change**: `ditherImageOrdered` now takes a `DitherKernel kernel`
  instead of a raw `List<List<double>> matrix`. The threshold matrix is resolved
  internally via `_orderedDitherMatrix`, so callers pass the kernel
  (e.g. `ditherImageOrdered(image, quantizer, DitherKernel.bayer4x4, strength)`)
  rather than the matrix itself. `ditherImageBayer` and `ditherImageBlueNoise`
  continue to work unchanged.
- ♻️ Refactored the ordered-dither branch detection in `ditherImage`: added a
  lightweight `_isOrderedDither` helper so the branch test no longer fetches the
  threshold matrix; the matrix is looked up only once, inside `ditherImageOrdered`.

## 1.0.1

- 🔗 Adjusted the image / badge links in the documentation.

## 1.0.0

- 🎛️ **8 dithering kernels** — error-diffusion (Floyd–Steinberg, Stucki, Atkinson,
  Jarvis–Judice–Ninke, Burkes, False Floyd–Steinberg (Heckbert)), ordered (Bayer 2×2/4×4/8×8,
  Blue Noise), and none (no dithering).
- 🔀 **4 scan orders** for error-diffusion kernels (raster, serpentine, zigzag, Hilbert
  space-filling curve).
- 🎨 **8 E-Ink palettes** — from pure black/white up to 7-color (Gallery 7) and 16-level
  grayscale (Carta 16).
- 🧮 Universal quantizer `EInkPaletteQuantizer` that maps any color to the nearest E-Ink
  color in a palette using Euclidean RGB distance.
- ⚙️ A configurable `EInkImageProcessor` with both synchronous (`process`) and isolate-based
  asynchronous (`processIsolated`) processing.