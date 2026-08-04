## 1.0.0

- **8 dithering kernels** — error-diffusion (Floyd–Steinberg, Stucki, Atkinson,
  Jarvis–Judice–Ninke, Burkes, False Floyd–Steinberg (Heckbert)), ordered (Bayer 2×2/4×4/8×8,
  Blue Noise), and none (no dithering).
- **4 scan orders** for error-diffusion kernels (raster, serpentine, zigzag, Hilbert
  space-filling curve).
- **8 E-Ink palettes** — from pure black/white up to 7-color (Gallery 7) and 16-level
  grayscale (Carta 16).
- Universal quantizer `EInkPaletteQuantizer` that maps any color to the nearest E-Ink
  color in a palette using Euclidean RGB distance.
- A configurable `EInkImageProcessor` with both synchronous (`process`) and isolate-based
  asynchronous (`processIsolated`) processing.