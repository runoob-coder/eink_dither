import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:eink_dither/eink_dither.dart';

void main() {
  runApp(const DemoApp());
}

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'E-Ink Dither Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.pinkAccent,
          brightness: .light,
        ),
        useMaterial3: true,
      ),
      home: const DitherDemoPage(),
    );
  }
}

enum _ViewMode { original, result }

class DitherDemoPage extends StatefulWidget {
  const DitherDemoPage({super.key});

  @override
  State<DitherDemoPage> createState() => _DitherDemoPageState();
}

class _DitherDemoPageState extends State<DitherDemoPage> {
  final ImagePicker _picker = ImagePicker();

  Uint8List? _originalBytes;
  Uint8List? _processedBytes;
  bool _isProcessing = false;
  bool _pendingReprocess = false;
  _ViewMode _viewMode = .original;
  _ViewMode _viewModeBeforeLongPress = .original;

  EInkPalette _selectedPalette = .spectra6;
  DitherKernel _selectedKernel = .floydSteinberg;
  DitherScanOrder _selectedScanOrder = .serpentine;
  double _intensity = 1.0;

  // ---------- display-name helpers ----------

  String _paletteLabel(EInkPalette p) => switch (p) {
    .bw => 'B/W (2 inks)',
    .spectra3Red => 'Spectra 3 (B/W/R)',
    .spectra3Yellow => 'Spectra 3 (B/W/Y)',
    .spectra4 => 'Spectra 4 (B/W/R/Y)',
    .spectra3100Plus => 'Spectra 3100 Plus',
    .spectra6 => 'Spectra 6',
    .gallery7 => 'Gallery 7',
    .carta16 => 'Carta 16 (16 grays)',
  };

  String _kernelLabel(DitherKernel k) => switch (k) {
    .none => 'None',
    .falseFloydSteinberg => 'False Floyd-Steinberg',
    .floydSteinberg => 'Floyd-Steinberg',
    .stucki => 'Stucki',
    .atkinson => 'Atkinson',
    .jarvisJudiceNinke => 'Jarvis-Judice-Ninke',
    .burkes => 'Burkes',
    .bayer2x2 => 'Bayer 2\u00d72',
    .bayer4x4 => 'Bayer 4\u00d74',
    .bayer8x8 => 'Bayer 8\u00d78',
    .blueNoise => 'Blue Noise',
  };

  String _scanOrderLabel(DitherScanOrder s) => switch (s) {
    .raster => 'Raster',
    .serpentine => 'Serpentine',
    .zigzag => 'Zigzag',
    .hilbert => 'Hilbert Curve',
  };

  // Scan order only matters for error-diffusion kernels. Ordered dithering
  // (none, Bayer matrices, blue noise) is position-independent, so the
  // scan-order control is hidden for those kernels.
  static const _kernelsWithoutScanOrder = {
    DitherKernel.none,
    DitherKernel.bayer2x2,
    DitherKernel.bayer4x4,
    DitherKernel.bayer8x8,
    DitherKernel.blueNoise,
  };

  bool get _scanOrderVisible =>
      !_kernelsWithoutScanOrder.contains(_selectedKernel);

  // Intensity (ordered-dither strength) only applies to the position-based
  // kernels — Bayer matrices and blue noise. Error-diffusion kernels and
  // `none` ignore it, so the slider is hidden for those.
  static const _kernelsWithIntensity = {
    DitherKernel.bayer2x2,
    DitherKernel.bayer4x4,
    DitherKernel.bayer8x8,
    DitherKernel.blueNoise,
  };

  bool get _intensityVisible => _kernelsWithIntensity.contains(_selectedKernel);

  List<Color> _paletteColors(EInkPalette p) =>
      p.colors.map((c) => Color.fromARGB(255, c.r, c.g, c.b)).toList();

  // ---------- actions ----------

  /// Load the bundled sample image (assets/design.png) for quick debugging
  /// without needing to pick from the gallery or camera.
  Future<void> _loadDefaultImage() async {
    try {
      final data = await rootBundle.load('assets/design.png');
      if (!mounted) return;
      setState(() {
        _originalBytes = data.buffer.asUint8List();
        _processedBytes = null;
        _viewMode = .original;
      });
      _processImage(); // auto-apply dithering to the sample
    } catch (e) {
      _showError('Failed to load sample image: $e');
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final xfile = await _picker.pickImage(source: source, maxWidth: 2048);
      if (xfile == null) return;

      final bytes = await xfile.readAsBytes();
      setState(() {
        _originalBytes = bytes;
        _processedBytes = null;
        _viewMode = .original;
      });
      _processImage(); // auto-apply dithering right after picking
    } catch (e) {
      _showError('Failed to pick image: $e');
    }
  }

  Future<void> _processImage() async {
    if (_originalBytes == null) return;

    // Avoid spawning overlapping isolates; remember that another run is needed.
    if (_isProcessing) {
      _pendingReprocess = true;
      return;
    }
    _isProcessing = true;
    if (mounted) {
      LoadingOverlay.show(context);
      setState(() {});
    }

    try {
      do {
        _pendingReprocess = false;

        final processor = EInkImageProcessor(
          palette: _selectedPalette,
          ditherKernel: _selectedKernel,
          scanOrder: _selectedScanOrder,
          intensity: _intensity,
          maxSize: 800,
        );

        final result = await processor.processIsolated(_originalBytes!);
        if (!mounted) return; // disposed; dispose() hides the overlay
        if (result != null) {
          _processedBytes = Uint8List.fromList(img.encodePng(result));
          _viewMode = .result;
        } else {
          _showError('Failed to decode or process image');
        }

        if (mounted) setState(() {});
      } while (_pendingReprocess && mounted);
    } catch (e) {
      if (mounted) _showError('Processing error: $e');
    } finally {
      _isProcessing = false;
      if (mounted) {
        LoadingOverlay.hide();
        setState(() {});
      }
    }
  }

  void _clearImage() {
    setState(() {
      _originalBytes = null;
      _processedBytes = null;
      _viewMode = _ViewMode.original;
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  // ---------- build ----------

  @override
  Widget build(BuildContext context) {
    final hasImage = _originalBytes != null;
    final hasResult = _processedBytes != null;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('E-Ink Dither Demo'),
        backgroundColor: colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.image_outlined),
            tooltip: 'Use sample image',
            onPressed: _loadDefaultImage,
          ),
          if (hasImage)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Clear image',
              onPressed: _clearImage,
            ),
          PopupMenuButton<ImageSource>(
            icon: const Icon(Icons.add_photo_alternate_outlined),
            tooltip: 'Pick image',
            onSelected: _pickImage,
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: .gallery,
                child: ListTile(
                  leading: Icon(Icons.photo_library_outlined),
                  title: Text('Gallery'),
                  contentPadding: .zero,
                ),
              ),
              PopupMenuItem(
                value: .camera,
                child: ListTile(
                  leading: Icon(Icons.camera_alt_outlined),
                  title: Text('Camera'),
                  contentPadding: .zero,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // view-mode toggle
          if (hasResult)
            Padding(
              padding: const .symmetric(horizontal: 16, vertical: 8),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<_ViewMode>(
                  segments: const [
                    ButtonSegment(
                      value: .original,
                      label: Text('Original'),
                      icon: Icon(Icons.image_outlined),
                    ),
                    ButtonSegment(
                      value: .result,
                      label: Text('Result'),
                      icon: Icon(Icons.auto_fix_high_outlined),
                    ),
                  ],
                  selected: {_viewMode},
                  onSelectionChanged: (v) =>
                      setState(() => _viewMode = v.first),
                ),
              ),
            ),

          // image display
          Expanded(child: _buildImageArea(hasImage, hasResult)),

          // config panel
          _buildConfigPanel(),
        ],
      ),
    );
  }

  // ---------- image area ----------

  Widget _buildImageArea(bool hasImage, bool hasResult) {
    final displayBytes = switch (_viewMode) {
      .original => _originalBytes,
      .result => _processedBytes,
    };
    // While reprocessing, keep showing the previous image (original or last
    // result) behind a dimmed spinner instead of blanking the screen.
    final backgroundBytes = displayBytes ?? _originalBytes;

    if (backgroundBytes == null) {
      return _buildPlaceholder();
    }

    final info = switch (_viewMode) {
      .original when hasResult =>
        'pinch to zoom \u00b7 long-press to compare with the result',
      .result => 'pinch to zoom \u00b7 long-press to compare with original',
      .original => 'Selected image',
    };

    return Column(
      children: [
        Padding(
          padding: const .only(top: 8),
          child: Text(
            info,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: GestureDetector(
            behavior: .translucent,
            onLongPressStart: (_) {
              if (!hasResult) return;
              _viewModeBeforeLongPress = _viewMode;
              setState(() {
                _viewMode = _viewMode == .original ? .result : .original;
              });
            },
            onLongPressEnd: (_) {
              if (!hasResult) return;
              setState(() => _viewMode = _viewModeBeforeLongPress);
            },
            child: InteractiveViewer(
              maxScale: 5.0,
              child: Center(
                child: Image.memory(
                  backgroundBytes,
                  fit: .contain,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.broken_image_outlined, size: 64),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlaceholder() {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const .all(32),
        child: Column(
          spacing: 16,
          mainAxisSize: .min,
          children: [
            Icon(Icons.image_outlined, size: 72, color: colorScheme.outline),
            Text(
              'Pick an image to get started',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: colorScheme.outline),
            ),
            Text(
              'Apply e-ink dithering effects with custom\npalettes, kernels, and scan orders.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.outline.withValues(alpha: 0.7),
              ),
            ),
            Column(
              mainAxisSize: .min,
              spacing: 4,
              children: [
                FilledButton.icon(
                  onPressed: () => _pickImage(.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Choose from Gallery'),
                ),
                OutlinedButton.icon(
                  onPressed: _loadDefaultImage,
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text('Use Sample Image'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------- config panel ----------

  Widget _buildConfigPanel() {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      padding: .fromLTRB(
        16,
        12,
        16,
        8 + MediaQuery.of(context).viewPadding.bottom,
      ),
      child: Column(
        mainAxisSize: .min,
        crossAxisAlignment: .center,
        spacing: 10,
        children: [
          _buildPaletteSwatches(),

          _buildPaletteDropdown(),
          // kernel + scan order row
          Row(
            spacing: 6,
            children: [
              Expanded(
                child: _buildDropdown<DitherKernel>(
                  value: _selectedKernel,
                  items: DitherKernel.values,
                  labelBuilder: _kernelLabel,
                  onChanged: _onKernelChanged,
                  leading: Icons.blur_on,
                ),
              ),
              if (_scanOrderVisible)
                Expanded(
                  child: _buildDropdown<DitherScanOrder>(
                    value: _selectedScanOrder,
                    items: DitherScanOrder.values,
                    labelBuilder: _scanOrderLabel,
                    onChanged: _onScanOrderChanged,
                    leading: Icons.swap_horiz,
                  ),
                ),
            ],
          ),
          if (_intensityVisible)
            Row(
              children: [
                const Icon(Icons.contrast, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Intensity',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Expanded(
                  child: Slider(
                    value: _intensity,
                    min: 0.0,
                    max: 2.0,
                    divisions: 40,
                    label: '${(_intensity * 100).round()}%',
                    onChanged: (v) => setState(() => _intensity = v),
                    onChangeEnd: (_) => _processImage(),
                  ),
                ),
                Text(
                  '${(_intensity * 100).round()}%',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildPaletteDropdown() {
    return DropdownButtonFormField<EInkPalette>(
      initialValue: _selectedPalette,
      decoration: InputDecoration(
        labelText: 'E-Ink Palette',
        prefixIcon: const Icon(Icons.palette_outlined, size: 20),
        border: OutlineInputBorder(borderRadius: .circular(10)),
        contentPadding: const .symmetric(horizontal: 12, vertical: 10),
      ),
      isExpanded: true,
      style: Theme.of(context).textTheme.bodyMedium,
      items: EInkPalette.values.map((p) {
        return DropdownMenuItem(value: p, child: Text(_paletteLabel(p)));
      }).toList(),
      onChanged: (v) {
        if (v != null) _onPaletteChanged(v);
      },
    );
  }

  Widget _buildPaletteSwatches() {
    final colors = _paletteColors(_selectedPalette);
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      alignment: .center,
      children: colors
          .map(
            (c) => Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: c,
                shape: .circle,
                border: Border.all(
                  color: Colors.black.withValues(alpha: 0.2),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: c.withValues(alpha: 0.4),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildDropdown<T extends Enum>({
    required T value,
    required List<T> items,
    required String Function(T) labelBuilder,
    required ValueChanged<T> onChanged,
    IconData? leading,
  }) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: T == DitherKernel ? 'Kernel' : 'Scan Order',
        prefixIcon: leading != null ? Icon(leading, size: 20) : null,
        border: OutlineInputBorder(borderRadius: .circular(10)),
        contentPadding: const .symmetric(horizontal: 12, vertical: 10),
      ),
      isExpanded: true,
      style: Theme.of(context).textTheme.bodyMedium,
      items: items.map((item) {
        return DropdownMenuItem(
          value: item,
          child: Text(labelBuilder(item), overflow: .visible),
        );
      }).toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }

  // ---------- config-change handlers (auto re-apply dithering) ----------

  void _onPaletteChanged(EInkPalette v) {
    if (_selectedPalette == v) return;
    setState(() => _selectedPalette = v);
    _processImage();
  }

  void _onKernelChanged(DitherKernel v) {
    if (_selectedKernel == v) return;
    setState(() => _selectedKernel = v);
    _processImage();
  }

  void _onScanOrderChanged(DitherScanOrder v) {
    if (_selectedScanOrder == v) return;
    setState(() => _selectedScanOrder = v);
    _processImage();
  }

  @override
  void dispose() {
    LoadingOverlay.hide();
    super.dispose();
  }
}

/// A global, imperative loading overlay inserted on top of the app's [Overlay].
/// Call [LoadingOverlay.show] / [LoadingOverlay.hide] to control it from
/// anywhere, without wrapping the widget tree in a [Stack].
class LoadingOverlay {
  LoadingOverlay._();

  static OverlayEntry? _entry;

  static void show(BuildContext context) {
    hide(); // ensure a single live entry
    _entry = OverlayEntry(
      builder: (_) => Material(
        color: Colors.black.withValues(alpha: 0.45),
        child: const Center(
          child: Card(
            child: Padding(
              padding: .all(20),
              child: Column(
                spacing: 12,
                mainAxisSize: .min,
                children: [
                  CircularProgressIndicator(),
                  Text('Processing image...'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_entry!);
  }

  static void hide() {
    _entry?.remove();
    _entry = null;
  }
}
