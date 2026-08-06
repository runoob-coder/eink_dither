import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img hide DitherKernel, ditherImage;

import 'dither_image.dart';
import 'dither_image.dart' as img;

/// Ink colors supported by e-ink displays.
enum EInkColor {
  black(0, 0, 0),
  white(255, 255, 255),
  red(255, 0, 0),
  yellow(255, 255, 0),
  green(0, 255, 0),
  blue(0, 0, 255),
  orange(255, 165, 0),
  // Inner steps of the 16-level gray ramp (level `i` renders as `i * 17`).
  // Both ends of the ramp are [black] (level 0) and [white] (level 15).
  gray1(17, 17, 17),
  gray2(34, 34, 34),
  gray3(51, 51, 51),
  gray4(68, 68, 68),
  gray5(85, 85, 85),
  gray6(102, 102, 102),
  gray7(119, 119, 119),
  gray8(136, 136, 136),
  gray9(153, 153, 153),
  gray10(170, 170, 170),
  gray11(187, 187, 187),
  gray12(204, 204, 204),
  gray13(221, 221, 221),
  gray14(238, 238, 238);

  const EInkColor(this.r, this.g, this.b);

  final int r;

  final int g;

  final int b;
}

/// E-ink palette types.
enum EInkPalette {
  bw([.black, .white]),
  spectra3Red([.black, .white, .red]),
  spectra3Yellow([.black, .white, .yellow]),
  spectra4([.black, .white, .red, .yellow]),
  spectra3100Plus([.black, .white, .red, .yellow, .orange]),
  spectra6([.black, .white, .red, .green, .blue, .yellow]),
  gallery7([.black, .white, .red, .yellow, .blue, .green, .orange]),

  /// E Ink Carta: monochrome panel with 16 gray levels, level `i`
  /// rendering as `i * 17` in sRGB.
  carta16([
      .black,
      .gray1,
      .gray2,
      .gray3,
      .gray4,
      .gray5,
      .gray6,
      .gray7,
      .gray8,
      .gray9,
      .gray10,
      .gray11,
      .gray12,
      .gray13,
      .gray14,
      .white,
  ]);

  const EInkPalette(this.colors);

  final List<EInkColor> colors;
}

/// E-ink palette quantizer: maps any color to the nearest color in the given palette.
/// Used with [img.ditherImage] for error-diffusion dithering to fit photos into the
/// limited ink colors of e-ink displays.
class EInkPaletteQuantizer extends img.Quantizer {
  EInkPaletteQuantizer(this.colors) {
    _palette = img.PaletteUint8(colors.length, 3);
    // Pre-store each color component in contiguous buffers for fast access in the
    // per-pixel hot loop of [getColorIndexRgb].
    _rs = Uint8List(colors.length);
    _gs = Uint8List(colors.length);
    _bs = Uint8List(colors.length);
    for (var i = 0; i < colors.length; i++) {
      final c = colors[i];
      _palette.setRgb(i, c.r, c.g, c.b);
      _rs[i] = c.r;
      _gs[i] = c.g;
      _bs[i] = c.b;
    }
  }

  /// Constructs from a palette type (e.g. [EInkPalette.spectra6]).
  EInkPaletteQuantizer.of(EInkPalette type) : this(type.colors);

  final List<EInkColor> colors;

  late final img.Palette _palette;
  late final Uint8List _rs;
  late final Uint8List _gs;
  late final Uint8List _bs;

  @override
  img.Palette get palette => _palette;

  @override
  int getColorIndexRgb(int r, int g, int b) {
    final rs = _rs;
    final gs = _gs;
    final bs = _bs;
    final n = rs.length;
    var best = 0;
    var bestDist = double.infinity;
    for (var i = 0; i < n; i++) {
      final dr = r - rs[i];
      final dg = g - gs[i];
      final db = b - bs[i];
      final dist = dr * dr + dg * dg + db * db;
      if (dist < bestDist) {
        bestDist = dist.toDouble();
        best = i;
      }
    }
    return best;
  }

  @override
  int getColorIndex(img.Color c) =>
      getColorIndexRgb(c.r.toInt(), c.g.toInt(), c.b.toInt());

  @override
  img.Color getQuantizedColor(img.Color c) {
    final idx = getColorIndex(c);
    return img.ColorRgb8(
      _palette.getRed(idx) as int,
      _palette.getGreen(idx) as int,
      _palette.getBlue(idx) as int,
    );
  }
}

/// E-ink image processor: quantizes a color image to a fixed palette and applies
/// error-diffusion dithering, returning an [img.Image].
///
/// [process] runs on the calling thread.
/// [processIsolated] runs in a [compute] isolate.
class EInkImageProcessor {
  const EInkImageProcessor({
    this.palette = EInkPalette.spectra6,
    this.ditherKernel = img.DitherKernel.floydSteinberg,
    this.scanOrder = DitherScanOrder.raster,
    this.intensity = 1.0,
    this.patternSize = 1,
    this.maxSize = 800,
  });

  /// Ink palette.
  final EInkPalette palette;

  /// Error-diffusion dithering kernel.
  final img.DitherKernel ditherKernel;

  /// Pixel visiting order used by the error-diffusion kernels.
  final img.DitherScanOrder scanOrder;

  /// Dither intensity for the ordered kernels (Bayer / blue noise).
  /// Scales the threshold offset; 1.0 is the standard intensity. The
  /// error-diffusion kernels ignore this value.
  final double intensity;

  /// Pattern size for every dithering kernel (all except [DitherKernel.none]).
  /// `1` is the classic 1:1 look; larger values make the dither pattern coarser
  /// / larger (similar to a halftone "Pattern Size" control).
  ///
  /// For the ordered kernels (Bayer / blue noise) each threshold-matrix cell
  /// covers [patternSize]×[patternSize] pixels instead of 1×1. For the
  /// error-diffusion kernels ([DitherKernel.floydSteinberg], [DitherKernel.stucki],
  /// etc.) the diffusion runs on a [patternSize]×[patternSize]-block downsampled
  /// grid and each block is expanded back, so the dither "dots" grow with
  /// [patternSize].
  final int patternSize;

  /// Maximum size (limits the longest side).
  final int maxSize;

  /// Processes the image on the current thread: resize -> quantize to fixed palette + dither.
  img.Image? process(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    var image = decoded;
    if (image.width > maxSize || image.height > maxSize) {
      // Pass only the longest side; img computes the other side proportionally.
      image = image.width >= image.height
          ? img.copyResize(image, width: maxSize)
          : img.copyResize(image, height: maxSize);
    }

    return img.ditherImage(
      image,
      quantizer: EInkPaletteQuantizer.of(palette),
      kernel: ditherKernel,
      scanOrder: scanOrder,
      intensity: intensity,
      patternSize: patternSize,
    );
  }

  /// Processes the image in a [compute] isolate (to avoid blocking the UI).
  Future<img.Image?> processIsolated(Uint8List bytes) =>
      compute(_run, (this, bytes));

  static img.Image? _run((EInkImageProcessor, Uint8List) args) =>
      args.$1.process(args.$2);
}
