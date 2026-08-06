import 'dart:math';
import 'package:image/image.dart' as img;

/// The pattern to use for dithering
enum DitherKernel {
  none,
  floydSteinberg,
  falseFloydSteinberg,
  jarvisJudiceNinke,
  stucki,
  burkes,
  atkinson,
  sierra3,
  sierra2,
  sierraLite,
  bayer2x2,
  bayer4x4,
  bayer8x8,
  blueNoise,
}

/// The order in which pixels are visited by the error-diffusion kernels.
enum DitherScanOrder {
  /// Standard raster scan: every row is traversed left to right, top to
  /// bottom.
  raster,

  /// Boustrophedon (snake) scan: the horizontal direction is reversed on
  /// every other row, which reduces directional artifacts.
  serpentine,

  /// Diagonal zigzag scan (the JPEG-style ordering): pixels are visited along
  /// anti-diagonals (`x + y == d`), alternating the direction of each
  /// diagonal. It spreads the error along both axes, which softens the
  /// horizontal worm patterns typical of raster scanning.
  zigzag,

  /// Hilbert space-filling curve scan: pixels are visited following the
  /// fractal Hilbert curve order, which maximizes spatial locality. Every
  /// pair of consecutive pixels is adjacent on the grid. This gives the best
  /// reduction of directional artifacts among deterministic scan orders and
  /// closely approximates random-walk error diffusion without sacrificing
  /// determinism.
  hilbert,
}

/// Error-diffusion dither kernels keyed by [DitherKernel].
///
/// Each kernel is a list of taps, where every tap is `[weight, offsetX,
/// offsetY]`: the [weight] (fraction of the quantization error) is propagated
/// to the neighbor at `(x + offsetX, y + offsetY)`.
///
/// The Bayer and blue-noise variants are not error-diffusion kernels and live
/// in [_bayerMatrices] / [_blueNoiseMask] instead.
const Map<DitherKernel, List<List<num>>> _errorDiffusionKernels = {
  // Placeholder for [DitherKernel.none]; it is never actually used because
  // [ditherImage] short-circuits before reaching the diffusion loop.
  DitherKernel.none: [
    [0, 0, 0],
    [0, 0, 0],
    [0, 0, 0],
  ],
  // Floyd-Steinberg
  DitherKernel.floydSteinberg: [
    [7 / 16, 1, 0],
    [3 / 16, -1, 1],
    [5 / 16, 0, 1],
    [1 / 16, 1, 1],
  ],
  // False Floyd-Steinberg (Heckbert)
  DitherKernel.falseFloydSteinberg: [
    [3 / 8, 1, 0],
    [3 / 8, 0, 1],
    [2 / 8, 1, 1],
  ],
  // Jarvis-Judice-Ninke
  DitherKernel.jarvisJudiceNinke: [
    [7 / 48, 1, 0],
    [5 / 48, 2, 0],
    [3 / 48, -2, 1],
    [5 / 48, -1, 1],
    [7 / 48, 0, 1],
    [5 / 48, 1, 1],
    [3 / 48, 2, 1],
    [1 / 48, -2, 2],
    [3 / 48, -1, 2],
    [5 / 48, 0, 2],
    [3 / 48, 1, 2],
    [1 / 48, 2, 2],
  ],
  // Stucki
  DitherKernel.stucki: [
    [8 / 42, 1, 0],
    [4 / 42, 2, 0],
    [2 / 42, -2, 1],
    [4 / 42, -1, 1],
    [8 / 42, 0, 1],
    [4 / 42, 1, 1],
    [2 / 42, 2, 1],
    [1 / 42, -2, 2],
    [2 / 42, -1, 2],
    [4 / 42, 0, 2],
    [2 / 42, 1, 2],
    [1 / 42, 2, 2],
  ],
  // Burkes
  DitherKernel.burkes: [
    [8 / 32, 1, 0],
    [4 / 32, 2, 0],
    [2 / 32, -2, 1],
    [4 / 32, -1, 1],
    [8 / 32, 0, 1],
    [4 / 32, 1, 1],
    [2 / 32, 2, 1],
  ],
  // Atkinson
  DitherKernel.atkinson: [
    [1 / 8, 1, 0],
    [1 / 8, 2, 0],
    [1 / 8, -1, 1],
    [1 / 8, 0, 1],
    [1 / 8, 1, 1],
    [1 / 8, 0, 2],
  ],
  // Sierra (Sierra-3), Frankie Sierra 1989
  DitherKernel.sierra3: [
    [5 / 32, 1, 0],
    [3 / 32, 2, 0],
    [2 / 32, -2, 1],
    [4 / 32, -1, 1],
    [5 / 32, 0, 1],
    [4 / 32, 1, 1],
    [2 / 32, 2, 1],
    [2 / 32, -1, 2],
    [3 / 32, 0, 2],
    [2 / 32, 1, 2],
  ],
  // Two-Row Sierra (Sierra-2)
  DitherKernel.sierra2: [
    [4 / 16, 1, 0],
    [3 / 16, 2, 0],
    [1 / 16, -2, 1],
    [2 / 16, -1, 1],
    [3 / 16, 0, 1],
    [2 / 16, 1, 1],
    [1 / 16, 2, 1],
  ],
  // Sierra Lite (Sierra-2-4-A)
  DitherKernel.sierraLite: [
    [2 / 4, 1, 0],
    [1 / 4, -1, 1],
    [1 / 4, 0, 1],
  ],
};

/// Ordered (Bayer) dither matrices with values normalized to [0, 1).
const _bayerMatrices = <DitherKernel, List<List<double>>>{
  DitherKernel.bayer2x2: [
    [0 / 4, 2 / 4],
    [3 / 4, 1 / 4],
  ],
  DitherKernel.bayer4x4: [
    [0 / 16, 8 / 16, 2 / 16, 10 / 16],
    [12 / 16, 4 / 16, 14 / 16, 6 / 16],
    [3 / 16, 11 / 16, 1 / 16, 9 / 16],
    [15 / 16, 7 / 16, 13 / 16, 5 / 16],
  ],
  DitherKernel.bayer8x8: [
    [0 / 64, 32 / 64, 8 / 64, 40 / 64, 2 / 64, 34 / 64, 10 / 64, 42 / 64],
    [48 / 64, 16 / 64, 56 / 64, 24 / 64, 50 / 64, 18 / 64, 58 / 64, 26 / 64],
    [12 / 64, 44 / 64, 4 / 64, 36 / 64, 14 / 64, 46 / 64, 6 / 64, 38 / 64],
    [60 / 64, 28 / 64, 52 / 64, 20 / 64, 62 / 64, 30 / 64, 54 / 64, 22 / 64],
    [3 / 64, 35 / 64, 11 / 64, 43 / 64, 1 / 64, 33 / 64, 9 / 64, 41 / 64],
    [51 / 64, 19 / 64, 59 / 64, 27 / 64, 49 / 64, 17 / 64, 57 / 64, 25 / 64],
    [15 / 64, 47 / 64, 7 / 64, 39 / 64, 13 / 64, 45 / 64, 5 / 64, 37 / 64],
    [63 / 64, 31 / 64, 55 / 64, 23 / 64, 61 / 64, 29 / 64, 53 / 64, 21 / 64],
  ],
};

/// Blue-noise dither mask generated once via void-and-cluster (Ulichney 1993).
/// Top-level `final` is lazily initialized in Dart — no manual caching needed.
final _blueNoiseMask = _generateBlueNoiseMask(64);

/// Generates a [size]×[size] blue-noise dither mask using the
/// void-and-cluster
/// algorithm with a Gaussian filter for local density estimation. The mask
/// values are normalized to [0, 1). Toroidal boundary conditions ensure the
/// mask tiles seamlessly.
List<List<double>> _generateBlueNoiseMask(int size) {
  final rng = Random(123456);
  final n = size * size;

  // Gaussian filter parameters — wider filter gives smoother blue noise.
  final filterRadius = max(1, size ~/ 10);
  final sigma = filterRadius / 2.0;
  final kernelSize = 2 * filterRadius + 1;

  // Build the 2-D Gaussian kernel.
  final List<List<double>> kernel = List.generate(
    kernelSize,
    (_) => List.filled(kernelSize, 0.0),
  );
  var kernelSum = 0.0;
  for (var ky = 0; ky < kernelSize; ky++) {
    for (var kx = 0; kx < kernelSize; kx++) {
      final dx = (kx - filterRadius).toDouble();
      final dy = (ky - filterRadius).toDouble();
      final v = exp(-(dx * dx + dy * dy) / (2 * sigma * sigma));
      kernel[ky][kx] = v;
      kernelSum += v;
    }
  }
  for (var ky = 0; ky < kernelSize; ky++) {
    for (var kx = 0; kx < kernelSize; kx++) {
      kernel[ky][kx] /= kernelSum;
    }
  }

  // Initial binary pattern: ~50 % ones, randomly placed.
  final binary = List.generate(size, (_) => List.filled(size, 0));
  final allIndices = List.generate(n, (i) => i)..shuffle(rng);
  var onesCount = 0;
  for (var i = 0; i < n ~/ 2; i++) {
    final idx = allIndices[i];
    binary[idx ~/ size][idx % size] = 1;
    onesCount++;
  }

  // Initial density map.
  final density = List.generate(size, (_) => List.filled(size, 0.0));
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      if (binary[y][x] == 1) {
        for (var ky = 0; ky < kernelSize; ky++) {
          final ty = (y + ky - filterRadius) % size;
          final dy = ty < 0 ? ty + size : ty;
          for (var kx = 0; kx < kernelSize; kx++) {
            final tx = (x + kx - filterRadius) % size;
            final dx = tx < 0 ? tx + size : tx;
            density[dy][dx] += kernel[ky][kx];
          }
        }
      }
    }
  }

  // Incrementally update the density map when pixel (cx, cy) is flipped.
  void updateDensity(int cx, int cy, double sign) {
    for (var ky = 0; ky < kernelSize; ky++) {
      final ty = (cy + ky - filterRadius) % size;
      final y = ty < 0 ? ty + size : ty;
      for (var kx = 0; kx < kernelSize; kx++) {
        final tx = (cx + kx - filterRadius) % size;
        final x = tx < 0 ? tx + size : tx;
        density[y][x] += sign * kernel[ky][kx];
      }
    }
  }

  // The rank assigned to each pixel; -1 means unassigned.
  final ranks = List.generate(size, (_) => List.filled(size, -1));

  for (var rank = 0; rank < n; rank++) {
    // At step [rank] we must have exactly [n - 1 - rank] ones.
    final targetOnes = n - 1 - rank;

    int bestX = 0, bestY = 0;

    if (onesCount < targetOnes) {
      // Need more ones: add at the largest void (0 with *minimum* density).
      var bestDensity = double.infinity;
      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          if (binary[y][x] == 0 &&
              ranks[y][x] == -1 &&
              density[y][x] < bestDensity) {
            bestDensity = density[y][x];
            bestX = x;
            bestY = y;
          }
        }
      }
      binary[bestY][bestX] = 1;
      updateDensity(bestX, bestY, 1.0);
      onesCount++;
    } else {
      // Need fewer ones: remove the tightest cluster (1 with max density).
      var bestDensity = -1.0;
      for (var y = 0; y < size; y++) {
        for (var x = 0; x < size; x++) {
          if (binary[y][x] == 1 &&
              ranks[y][x] == -1 &&
              density[y][x] > bestDensity) {
            bestDensity = density[y][x];
            bestX = x;
            bestY = y;
          }
        }
      }
      binary[bestY][bestX] = 0;
      updateDensity(bestX, bestY, -1.0);
      onesCount--;
    }

    ranks[bestY][bestX] = rank;
  }

  // Normalize thresholds to [0, 1).
  return List.generate(
    size,
    (y) => List.generate(size, (x) => ranks[y][x] / n),
  );
}

/// Dither an image to reduce banding patterns when reducing the number of
/// colors.
/// Derived from http://jsbin.com/iXofIji/2/edit
///
/// [quantizer] is the color reducer used to map each pixel to the palette;
/// if `null` a [NeuralQuantizer] is built from [image].
///
/// [kernel] selects the dithering algorithm: error-diffusion kernels
/// (e.g. [DitherKernel.floydSteinberg]) propagate quantization error to
/// neighbors, while the ordered Bayer kernels ([DitherKernel.bayer2x2],
/// [DitherKernel.bayer4x4], [DitherKernel.bayer8x8]) and blue noise
/// ([DitherKernel.blueNoise]) use a fixed position-based threshold matrix.
///
/// [scanOrder] selects the order in which pixels are visited by the
/// error-diffusion kernels ([DitherScanOrder.raster],
/// [DitherScanOrder.serpentine], the diagonal [DitherScanOrder.zigzag], or
/// the space-filling [DitherScanOrder.hilbert] curve).
/// It has no effect on the Bayer kernels.
///
/// [intensity] scales the dither offset and is only used for the ordered
/// kernels ([DitherKernel.bayer2x2], [DitherKernel.bayer4x4],
/// [DitherKernel.bayer8x8] and [DitherKernel.blueNoise]); it is ignored by
/// the error-diffusion kernels.
///
/// [patternSize] scales the dither pattern, making it coarser / larger (similar
/// to the "Pattern Size" control in many halftone editors). `1` reproduces the
/// classic 1:1 look.
///
/// For the ordered kernels ([DitherKernel.bayer2x2], [DitherKernel.bayer4x4],
/// [DitherKernel.bayer8x8] and [DitherKernel.blueNoise]) each threshold-matrix
/// cell covers [patternSize]×[patternSize] pixels instead of 1×1. For the
/// error-diffusion kernels ([DitherKernel.floydSteinberg], [DitherKernel.stucki],
/// etc.) the diffusion is run on a [patternSize]×[patternSize]-block
/// downsampled grid and each block is then expanded back, so the dither "dots"
/// grow with [patternSize].
img.Image ditherImage(
  img.Image image, {
  img.Quantizer? quantizer,
  DitherKernel kernel = DitherKernel.floydSteinberg,
  @Deprecated(
    'Use scanOrder: DitherScanOrder.serpentine instead. '
    'This parameter will be removed in a future release.',
  )
  bool serpentine = false,
  DitherScanOrder scanOrder = DitherScanOrder.zigzag,
  double intensity = 1.0,
  int patternSize = 1,
}) {
  quantizer ??= img.NeuralQuantizer(image);

  if (kernel == DitherKernel.none) {
    return quantizer.getIndexImage(image);
  }

  if (_isOrderedDither(kernel)) {
    return ditherImageOrdered(
      image,
      quantizer,
      kernel,
      intensity,
      patternSize: patternSize,
    );
  }

  final order = serpentine
      // ignore: deprecated_member_use_from_same_package
      ? DitherScanOrder.serpentine
      : scanOrder;

  // Error-diffusion kernels. With [patternSize] > 1 the diffusion is run on a
  // [patternSize]×[patternSize]-block downsampled grid and each block is then
  // expanded back, growing the dither "dots" (a "Pattern Size" control). The
  // diffusion core below is reused via the [patternSize] == 1 recursion, so no
  // diffusion logic is duplicated.
  if (patternSize > 1) {
    final ps = patternSize;

    // Build the reduced image by averaging each block.
    var rSum = 0;
    var gSum = 0;
    var bSum = 0;
    var count = 0;
    final reduced = img.Image(
      width: (image.width + ps - 1) ~/ ps,
      height: (image.height + ps - 1) ~/ ps,
      numChannels: 3,
    );
    _forEachBlockPixel(image.width, image.height, ps,
      (bx, by) {
        rSum = gSum = bSum = count = 0;
      },
      (bx, by, x, y) {
        final pc = image.getPixel(x, y);
        rSum += pc.r.toInt();
        gSum += pc.g.toInt();
        bSum += pc.b.toInt();
        count++;
      },
      (bx, by) {
        reduced.setPixelRgb(bx, by, rSum ~/ count, gSum ~/ count, bSum ~/ count);
      },
    );

    // Diffuse the coarse grid (recursion terminates: [patternSize] == 1).
    final reducedIndexed = ditherImage(
      reduced,
      quantizer: quantizer,
      kernel: kernel,
      scanOrder: order,
    );

    // Expand each reduced pixel into a [ps]×[ps] block of the same index.
    var index = 0;
    final out = img.Image(
      width: image.width,
      height: image.height,
      numChannels: 1,
      palette: quantizer.palette,
    );
    _forEachBlockPixel(image.width, image.height, ps,
      (bx, by) {
        index = reducedIndexed.getPixelIndex(bx, by);
      },
      (bx, by, x, y) {
        out.setPixelIndex(x, y, index);
      },
      (bx, by) {},
    );

    return out;
  }

  final q = quantizer;
  final ds = _errorDiffusionKernels[kernel]!;
  final height = image.height;
  final width = image.width;

  final palette = quantizer.palette;
  final indexedImage = img.Image(
    width: width,
    height: height,
    numChannels: 1,
    palette: palette,
  );

  final imageCopy = image.clone();

  // Quantizes the pixel at [x],[y] and diffuses its error to the neighbors.
  // [direction] is the horizontal scan direction (1 or -1) and controls the
  // order in which the kernel taps are applied.
  void diffusePixel(int x, int y, int direction) {
    // Get original color
    final pc = imageCopy.getPixel(x, y);
    final r1 = pc[0].toInt();
    final g1 = pc[1].toInt();
    final b1 = pc[2].toInt();

    // Get converted color
    final idx = q.getColorIndexRgb(r1, g1, b1);
    indexedImage.setPixelIndex(x, y, idx);

    final r2 = palette.get(idx, 0);
    final g2 = palette.get(idx, 1);
    final b2 = palette.get(idx, 2);

    final er = r1 - r2;
    final eg = g1 - g2;
    final eb = b1 - b2;

    if (er == 0 && eg == 0 && eb == 0) {
      return;
    }

    final i0 = direction == 1 ? 0 : ds.length - 1;
    final i1 = direction == 1 ? ds.length : 0;
    for (var i = i0; i != i1; i += direction) {
      final x1 = ds[i][1].toInt();
      final y1 = ds[i][2].toInt();
      if ((x1 + x) >= 0 &&
          (x1 + x) < width &&
          (y1 + y) >= 0 &&
          (y1 + y) < height) {
        final d = ds[i][0];
        final nx = x + x1;
        final ny = y + y1;
        final p2 = imageCopy.getPixel(nx, ny);
        p2
          ..r = p2.r + er * d
          ..g = p2.g + eg * d
          ..b = p2.b + eb * d;
      }
    }
  }

  if (order == DitherScanOrder.zigzag) {
    // Walk the anti-diagonals x + y == d, alternating their direction.
    final numDiagonals = width + height - 1;
    for (var d = 0; d < numDiagonals; d++) {
      final xMin = d < height ? 0 : d - height + 1;
      final xMax = d < width ? d : width - 1;
      if (d.isEven) {
        for (var x = xMin; x <= xMax; x++) {
          diffusePixel(x, d - x, 1);
        }
      } else {
        for (var x = xMax; x >= xMin; x--) {
          diffusePixel(x, d - x, 1);
        }
      }
    }
    return indexedImage;
  }

  if (order == DitherScanOrder.hilbert) {
    // Walk pixels in Hilbert space-filling curve order.
    // The curve is defined on a power-of-2 square; pixels outside the image
    // bounds are simply skipped.
    final maxDim = max(width, height);
    var n = 1;
    while (n < maxDim) {
      n <<= 1;
    }
    final xy = [0, 0];
    final total = n * n;
    for (var d = 0; d < total; d++) {
      _hilbertDtoXY(n, d, xy);
      if (xy[0] < width && xy[1] < height) {
        diffusePixel(xy[0], xy[1], 1);
      }
    }
    return indexedImage;
  }

  final isSerpentine = order == DitherScanOrder.serpentine;
  var direction = isSerpentine ? -1 : 1;

  for (var y = 0; y < height; y++) {
    if (isSerpentine) {
      direction = direction * -1;
    }

    final x0 = direction == 1 ? 0 : width - 1;
    final x1 = direction == 1 ? width : 0;
    for (var x = x0; x != x1; x += direction) {
      diffusePixel(x, y, direction);
    }
  }

  return indexedImage;
}

/// Walks every pixel in every [ps]×[ps] block of a 2D image grid, calling
/// [onBlockStart], [onPixel], and [onBlockEnd] for each block. Coordinates
/// `(x, y)` refer to the original image; `(bx, by)` are block indices.
///
/// This iterator eliminates the duplication of the 5-level nested loop +
/// bounds-check pattern that was previously repeated in the down-sampling and
/// expansion stages of the error-diffusion [patternSize] > 1 path.
void _forEachBlockPixel(
  int imageW,
  int imageH,
  int ps,
  void Function(int bx, int by) onBlockStart,
  void Function(int bx, int by, int x, int y) onPixel,
  void Function(int bx, int by) onBlockEnd,
) {
  final rw = (imageW + ps - 1) ~/ ps;
  final rh = (imageH + ps - 1) ~/ ps;
  for (var by = 0; by < rh; by++) {
    for (var bx = 0; bx < rw; bx++) {
      onBlockStart(bx, by);
      for (var dy = 0; dy < ps; dy++) {
        final y = by * ps + dy;
        if (y >= imageH) break;
        for (var dx = 0; dx < ps; dx++) {
          final x = bx * ps + dx;
          if (x >= imageW) break;
          onPixel(bx, by, x, y);
        }
      }
      onBlockEnd(bx, by);
    }
  }
}

/// Returns the threshold matrix for an ordered-dither [kernel], or `null`
/// if [kernel] is not an ordered-dither variant.
List<List<double>>? _orderedDitherMatrix(DitherKernel kernel) {
  if (_bayerMatrices.containsKey(kernel)) {
    return _bayerMatrices[kernel];
  }
  if (kernel == DitherKernel.blueNoise) {
    return _blueNoiseMask;
  }
  return null;
}

/// Returns `true` if [kernel] is an ordered-dither variant (a Bayer matrix or
/// [DitherKernel.blueNoise]), without fetching the threshold matrix itself.
bool _isOrderedDither(DitherKernel kernel) =>
    _bayerMatrices.containsKey(kernel) || kernel == DitherKernel.blueNoise;

/// Shared ordered-dither implementation for both Bayer and blue-noise masks.
///
/// [kernel] selects the ordered-dither pattern and must be one of the Bayer
/// variants ([DitherKernel.bayer2x2], [DitherKernel.bayer4x4],
/// [DitherKernel.bayer8x8]) or [DitherKernel.blueNoise]. Passing any other
/// [DitherKernel] triggers an assertion failure. The threshold matrix is
/// resolved internally via [_orderedDitherMatrix] from [kernel].
///
/// [patternSize] scales the threshold matrix: each matrix cell covers
/// [patternSize]×[patternSize] pixels instead of 1×1, stretching the dither
/// pattern to be coarser / larger. `1` reproduces the classic 1:1 look.
img.Image ditherImageOrdered(
  img.Image image,
  img.Quantizer? quantizer,
  DitherKernel kernel,
  double intensity, {
  int patternSize = 1,
}) {
  final matrix = _orderedDitherMatrix(kernel);
  assert(
    matrix != null,
    'kernel must be an ordered-dither variant: a Bayer matrix or blueNoise',
  );

  quantizer ??= img.NeuralQuantizer(image);

  final n = matrix!.length;
  final height = image.height;
  final width = image.width;
  final palette = quantizer.palette;
  final indexedImage = img.Image(
    width: width,
    height: height,
    numChannels: 1,
    palette: palette,
  );

  // Each threshold cell covers [ps]×[ps] pixels, so the pattern is stretched.
  final ps = patternSize < 1 ? 1 : patternSize;

  for (var y = 0; y < height; y++) {
    final row = matrix[(y ~/ ps) % n];
    for (var x = 0; x < width; x++) {
      final pc = image.getPixel(x, y);
      // Centered threshold in the range [-0.5, 0.5).
      final t = row[(x ~/ ps) % n] - 0.5;
      final d = t * 255 * intensity;
      final r = _clampChannel(pc[0] + d);
      final g = _clampChannel(pc[1] + d);
      final b = _clampChannel(pc[2] + d);
      final idx = quantizer.getColorIndexRgb(r, g, b);
      indexedImage.setPixelIndex(x, y, idx);
    }
  }

  return indexedImage;
}

/// Dither an image using an ordered (Bayer) threshold matrix. Unlike the
/// error-diffusion kernels, the dither pattern is position-based and does not
/// propagate error to neighboring pixels, making it deterministic and fast.
///
/// [kernel] must be one of the Bayer variants ([DitherKernel.bayer2x2],
/// [DitherKernel.bayer4x4] or [DitherKernel.bayer8x8]); passing any other
/// [DitherKernel] will trigger an assertion failure.
///
/// [quantizer] is the color reducer used to map each pixel to the palette;
/// if `null` (the default) a [NeuralQuantizer] is built from [image].
///
/// [intensity] scales the dither offset (defaults to 1.0 for the classic
/// full-range Bayer look; smaller values give subtler banding reduction).
///
/// [patternSize] scales the threshold matrix: each matrix cell covers
/// [patternSize]×[patternSize] pixels instead of 1×1, stretching the dither
/// pattern to be coarser / larger. `1` reproduces the classic 1:1 look.
img.Image ditherImageBayer(
  img.Image image, [
  img.Quantizer? quantizer,
  DitherKernel kernel = DitherKernel.bayer4x4,
  double intensity = 1.0,
  int patternSize = 1,
]) {
  assert(
    _bayerMatrices.containsKey(kernel),
    'kernel must be a Bayer variant: bayer2x2, bayer4x4 or bayer8x8',
  );
  return ditherImageOrdered(
    image,
    quantizer,
    kernel,
    intensity,
    patternSize: patternSize,
  );
}

/// Dither an image using a blue-noise threshold mask. Unlike Bayer matrices,
/// blue noise distributes error in a less structured, visually pleasing
/// high-frequency pattern that avoids the grid artifacts of ordered dithering.
///
/// The mask is a 64×64 tile generated once via the void-and-cluster algorithm
/// and reused across calls.
///
/// [quantizer] is the color reducer used to map each pixel to the palette;
/// if `null` (the default) a [NeuralQuantizer] is built from [image].
///
/// [intensity] scales the dither offset (defaults to 1.0 for the full-range
/// look; smaller values give subtler banding reduction).
///
/// [patternSize] scales the threshold matrix: each matrix cell covers
/// [patternSize]×[patternSize] pixels instead of 1×1, stretching the dither
/// pattern to be coarser / larger. `1` reproduces the classic 1:1 look.
img.Image ditherImageBlueNoise(
  img.Image image, [
  img.Quantizer? quantizer,
  double intensity = 1.0,
  int patternSize = 1,
]) {
  return ditherImageOrdered(
    image,
    quantizer,
    DitherKernel.blueNoise,
    intensity,
    patternSize: patternSize,
  );
}

/// Converts a Hilbert curve index [d] to (x, y) coordinates for an [n]×[n]
/// grid, where [n] MUST be a power of 2. The result is written into [out]
/// in-place ([out][0] = x, [out][1] = y) to avoid per-pixel allocations.
void _hilbertDtoXY(int n, int d, List<int> out) {
  out[0] = 0;
  out[1] = 0;
  int t = d;
  for (var s = 1; s < n; s <<= 1) {
    final rx = (t >> 1) & 1;
    final ry = (t ^ rx) & 1;
    if (ry == 0) {
      if (rx == 1) {
        out[0] = s - 1 - out[0];
        out[1] = s - 1 - out[1];
      }
      final temp = out[0];
      out[0] = out[1];
      out[1] = temp;
    }
    out[0] += s * rx;
    out[1] += s * ry;
    t >>= 2;
  }
}

int _clampChannel(num v) => v.clamp(0, 255).round();
