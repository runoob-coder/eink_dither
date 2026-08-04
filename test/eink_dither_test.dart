import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;

import 'package:eink_dither/src/eink_dither.dart';
import 'package:eink_dither/src/dither_image.dart';

void main() {
  final assetPath = 'assets/design.PNG';
  final outputDir = Directory('result');

  test(
    'process design.png with all dither algorithms and scan orders',
    () async {
      // Ensure output directory exists, clearing any existing images
      if (outputDir.existsSync()) {
        for (final f in outputDir.listSync()) {
          if (f is File && f.path.toLowerCase().endsWith('.png')) {
            f.deleteSync();
          }
        }
      } else {
        outputDir.createSync(recursive: true);
      }

      // Load the original image bytes once
      final originalBytes = await File(assetPath).readAsBytes();

      // Kernels that ignore scan order (ordered dithering / no dithering)
      const noScanOrder = {
        DitherKernel.none,
        DitherKernel.bayer2x2,
        DitherKernel.bayer4x4,
        DitherKernel.bayer8x8,
        DitherKernel.blueNoise,
      };

      // All scan orders for error-diffusion kernels
      final scanOrders = DitherScanOrder.values;

      var count = 0;

      for (final kernel in DitherKernel.values) {
        if (noScanOrder.contains(kernel)) {
          // Scan order has no effect; just generate one file
          final processor = EInkImageProcessor(
            palette: EInkPalette.spectra6,
            ditherKernel: kernel,
            maxSize: 700,
          );

          final processed = processor.process(originalBytes);
          expect(processed, isNotNull, reason: 'Failed for $kernel');

          final encoded = image_lib.encodePng(processed!);
          final fileName = '${kernel.name}.png';
          File('${outputDir.path}/$fileName').writeAsBytesSync(encoded);
          print('Saved: $fileName');
          count++;
        } else {
          for (final order in scanOrders) {
            final processor = EInkImageProcessor(
              palette: EInkPalette.spectra6,
              ditherKernel: kernel,
              scanOrder: order,
              maxSize: 700,
            );

            final processed = processor.process(originalBytes);
            expect(processed, isNotNull, reason: 'Failed for $kernel + $order');

            final encoded = image_lib.encodePng(processed!);
            final fileName = '${kernel.name}_${order.name}.png';
            File('${outputDir.path}/$fileName').writeAsBytesSync(encoded);
            print('Saved: $fileName');
            count++;
          }
        }
      }

      print('All $count images saved to ${outputDir.path}/');
    },
  );
}
