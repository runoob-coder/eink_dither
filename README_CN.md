# 📟 EInk Dither

一个用于**有限色 / 双色输出设备**图像处理的 Dart/Flutter 包。能把全彩图像**量化**到
目标设备的调色板，同时最大限度地减少色带与轮廓瑕疵。典型应用场景包括**墨水屏（E-Ink / 电子纸）**、
热敏打印机、LED / 点阵屏幕等。

[![Pub Version](https://img.shields.io/pub/v/eink_dither.svg)](https://pub.dev/packages/eink_dither)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Flutter Demo](https://img.shields.io/badge/demo-Flutter-brightgreen.svg)](https://runoob-coder.github.io/eink_dither/)
[![API Reference](https://img.shields.io/badge/API-Reference-0175C2.svg)](https://pub-web.flutter-io.cn/documentation/eink_dither/latest/)
[![GitHub stars](https://img.shields.io/github/stars/runoob-coder/eink_dither.svg?style=social)](https://github.com/runoob-coder/eink_dither)

Language: [English](README.md) | 中文

## ✨ 特性

- **13 种抖动算法**——误差扩散类（Floyd–Steinberg、Stucki、Atkinson、
  Jarvis–Judice–Ninke、Burkes、False Floyd–Steinberg（Heckbert）、Sierra-3、Two-Row Sierra、
  Sierra Lite（Sierra-2-4-A））、有序类（拜耳矩阵 Bayer 2×2 / 4×4 / 8×8、蓝噪声），以及无抖动（none）。
- **4 种扫描顺序（scan order）**——用于误差扩散算法（raster、serpentine、zigzag、
  Hilbert 空间填充曲线）。
- **8 种墨水屏调色板**——从纯黑白到 7 色（Gallery 7）以及 16 级灰度（Carta 16）。
- 墨水屏通用量化器 `EInkPaletteQuantizer`：按 RGB 欧氏距离把任意颜色映射到调色板中最近的墨水屏颜色。
- 可配置的 `EInkImageProcessor`，同时提供同步（`process`）与基于 isolate 的
  异步（`processIsolated`）处理方式。

## 📦 安装

通过 pub.dev 安装 → [pub.dev/packages/eink_dither/install](https://pub-web.flutter-io.cn/packages/eink_dither/install)

## 🚀 快速开始

[在线演示 — 立即体验](https://runoob-coder.github.io/eink_dither/)

```dart
import 'dart:typed_data';
import 'dart:io';
import 'package:eink_dither/eink_dither.dart';

Future<void> main() async {
  final Uint8List bytes = await File('photo.jpg').readAsBytes();

  // 1. 配置处理器。
  final processor = EInkImageProcessor(
    palette: EInkPalette.spectra6,
    ditherKernel: DitherKernel.floydSteinberg,
    scanOrder: DitherScanOrder.serpentine,
    intensity: 1.0,
    patternSize: 1,
    maxSize: 700,
  );

  // 2a. 同步处理（阻塞当前线程）。
  final image = processor.process(bytes);

  // 2b. 在 compute isolate 中异步处理（UI 推荐用法）。
  final image2 = await processor.processIsolated(bytes);

  // 3. 编码结果（如输出 PNG）。
  if (image2 != null) {
    final png = img.encodePng(image2); // 来自 image 包
    await File('out.png').writeAsBytes(png);
  }
}
```

## 📚 [API 参考](https://pub-web.flutter-io.cn/documentation/eink_dither/latest/)

### 🌈 `EInkColor`

可渲染墨水屏颜色的枚举。包含 CMY/RGB 三原色、`橙色`，以及一条 16 级灰度阶梯
（`gray1` … `gray14`，第 `i` 级在 sRGB 中渲染为 `i * 17`）。

### 🎨 `EInkPalette`

预置调色板枚举：

| 调色板               | 墨水屏颜色数 | 颜色                   |
|-------------------|:------:|----------------------|
| `bw`              |   2    | 黑、白                  |
| `spectra3Red`     |   3    | 黑、白、红                |
| `spectra3Yellow`  |   3    | 黑、白、黄                |
| `spectra4`        |   4    | 黑、白、红、黄              |
| `spectra3100Plus` |   5    | 黑、白、红、黄、橙            |
| `spectra6`        |   6    | 黑、白、红、绿、蓝、黄          |
| `gallery7`        |   7    | 黑、白、红、黄、蓝、绿、橙        |
| `carta16`         |   16   | 黑 + 14 级灰（`i*17`）+ 白 |

### 🔢 `EInkPaletteQuantizer`

`image` 包的 `Quantizer` 实现，按 RGB 欧氏距离把每个像素映射到调色板中最近的墨水屏颜色。
可直接构造：

```dart

final quantizer = EInkPaletteQuantizer([EInkColor.black, EInkColor.white]);
// 或从预置类型构造：
final q2 = EInkPaletteQuantizer.of(EInkPalette.spectra6);
```

### ⚙️ `EInkImageProcessor`

`process` 在调用线程执行；`processIsolated` 在 `compute` isolate 中执行，避免阻塞 UI。

| 属性             | 类型                | 默认值                           | 说明                        |
|----------------|-------------------|-------------------------------|---------------------------|
| `palette`      | `EInkPalette`     | `EInkPalette.spectra6`        | 目标墨水屏颜色调色板。               |
| `ditherKernel` | `DitherKernel`    | `DitherKernel.floydSteinberg` | 抖动算法。                     |
| `scanOrder`    | `DitherScanOrder` | `DitherScanOrder.zigzag`      | 像素遍历顺序（仅误差扩散类生效）。         |
| `intensity`    | `double`          | `1.0`                         | 有序算法的抖动强度；误差扩散算法忽略此值。     |
| `patternSize`  | `int`             | `1`                           | 缩放有序抖动的阈值单元或误差扩散的块（越大越粗）。 |
| `maxSize`      | `int`             | `800`                         | 最长边被限制为该值（等比缩放）。          |

```dart
img.Image? process(Uint8List bytes);

Future<img.Image?> processIsolated(Uint8List bytes);
```

### 🎛️ `DitherKernel`

抖动算法枚举。误差扩散算法（除 `none` 外）将量化误差传播给邻居；有序算法
（`bayer2x2`、`bayer4x4`、`bayer8x8`、`blueNoise`）使用固定的阈值矩阵，与位置无关。

```dart
enum DitherKernel {
  none,
  falseFloydSteinberg,
  floydSteinberg,
  stucki,
  atkinson,
  jarvisJudiceNinke,
  burkes,
  sierra3,
  sierra2,
  sierraLite,
  bayer2x2,
  bayer4x4,
  bayer8x8,
  blueNoise,
}
```

Sierra 系列（由 Frankie Sierra 提出）随着核尺寸缩小，以质量换取速度：

| 算法           | 别名              | 扩散邻居数 | 除数 | 说明                                 |
|--------------|-----------------|:-----:|:--:|------------------------------------|
| `sierra3`    | Sierra、Sierra-3 |  10   | 32 | 三行卷积核，质量接近 Jarvis，但速度明显更快。         |
| `sierra2`    | Two-Row Sierra  |   7   | 16 | 两行卷积核，质量与速度的良好折中。                  |
| `sierraLite` | Sierra-2-4-A    |   3   | 4  | 最小的变体，速度最快；颗粒感略强于 Floyd–Steinberg。 |

### 🔀 `DitherScanOrder`

误差扩散算法遍历像素的顺序。**对有序（Bayer / 蓝噪声）算法无影响**。

| 扫描顺序         | 说明                                                                                 |
|--------------|------------------------------------------------------------------------------------|
| `raster`     | 标准光栅扫描：每一行从左至右、从上至下遍历。                                                             |
| `serpentine` | 蛇形/往返扫描：每隔一行反转水平方向，减少方向性伪影。                                                        |
| `zigzag`     | 对角锯齿扫描（JPEG 式排布）：沿反对角线 `x + y == d` 遍历，逐条对角线交替方向，柔化光栅扫描典型的横向"蠕虫纹理"。                |
| `hilbert`    | Hilbert 空间填充曲线：像素按分形顺序访问，相邻像素在网格上紧邻，最大化空间局部性；在所有确定性扫描中方向性伪影抑制最佳，且近似随机游走误差扩散而不失确定性。 |

![误差扩散算法遍历像素顺序](https://github.com/runoob-coder/eink_dither/raw/main/dither_scans.png)

## 🖼️ 算法效果示例

以下预览均使用 `EInkPalette.spectra6`、`maxSize: 700` 生成。

### 🟦 有序抖动

有序抖动算法忽略 `scanOrder` 参数；支持 `intensity`（阈值强度）与 `patternSize`（阈值单元缩放）调节。

| `none`（无抖动）                                                                                   | `bayer2x2`                                                                                        | `bayer4x4`                                                                                        | `bayer8x8`                                                                                        | `blueNoise`                                                                                        |
|-----------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------|
| <img src="https://github.com/runoob-coder/eink_dither/raw/main/result/none.png" width="200"/> | <img src="https://github.com/runoob-coder/eink_dither/raw/main/result/bayer2x2.png" width="200"/> | <img src="https://github.com/runoob-coder/eink_dither/raw/main/result/bayer4x4.png" width="200"/> | <img src="https://github.com/runoob-coder/eink_dither/raw/main/result/bayer8x8.png" width="200"/> | <img src="https://github.com/runoob-coder/eink_dither/raw/main/result/blueNoise.png" width="200"/> |

### 🌊 误差扩散抖动

不同的 `算法 × 扫描顺序` 的组合产生不同的纹理效果。

| 算法 ↓ / 扫描 →                         | Raster（光栅）                                                                                                          | Serpentine（蛇形/往返）                                                                                                       | Zigzag（对角锯齿）                                                                                                        | Hilbert（希尔伯特曲线）                                                                                                      |
|-------------------------------------|---------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------------------------|
| **Floyd–Steinberg**                 | <img src="https://github.com/runoob-coder/eink_dither/raw/main/result/floydSteinberg_raster.png" width="200"/>      | <img src="https://github.com/runoob-coder/eink_dither/raw/main/result/floydSteinberg_serpentine.png" width="200"/>      | <img src="https://github.com/runoob-coder/eink_dither/raw/main/result/floydSteinberg_zigzag.png" width="200"/>      | <img src="https://github.com/runoob-coder/eink_dither/raw/main/result/floydSteinberg_hilbert.png" width="200"/>      |
| **False Floyd–Steinberg（Heckbert）** | <img src="https://github.com/runoob-coder/eink_dither/raw/main/result/falseFloydSteinberg_raster.png" width="200"/> | <img src="https://github.com/runoob-coder/eink_dither/raw/main/result/falseFloydSteinberg_serpentine.png" width="200"/> | <img src="https://github.com/runoob-coder/eink_dither/raw/main/result/falseFloydSteinberg_zigzag.png" width="200"/> | <img src="https://github.com/runoob-coder/eink_dither/raw/main/result/falseFloydSteinberg_hilbert.png" width="200"/> |
| **Stucki**                          | <img src="https://github.com/runoob-coder/eink_dither/raw/main/result/stucki_raster.png" width="200"/>              | <img src="https://github.com/runoob-coder/eink_dither/raw/main/result/stucki_serpentine.png" width="200"/>              | <img src="https://github.com/runoob-coder/eink_dither/raw/main/result/stucki_zigzag.png" width="200"/>              | <img src="https://github.com/runoob-coder/eink_dither/raw/main/result/stucki_hilbert.png" width="200"/>              |
| **Atkinson**                        | <img src="https://github.com/runoob-coder/eink_dither/raw/main/result/atkinson_raster.png" width="200"/>            | <img src="https://github.com/runoob-coder/eink_dither/raw/main/result/atkinson_serpentine.png" width="200"/>            | <img src="https://github.com/runoob-coder/eink_dither/raw/main/result/atkinson_zigzag.png" width="200"/>            | <img src="https://github.com/runoob-coder/eink_dither/raw/main/result/atkinson_hilbert.png" width="200"/>            |
| **Jarvis–Judice–Ninke**             | <img src="https://github.com/runoob-coder/eink_dither/raw/main/result/jarvisJudiceNinke_raster.png" width="200"/>   | <img src="https://github.com/runoob-coder/eink_dither/raw/main/result/jarvisJudiceNinke_serpentine.png" width="200"/>   | <img src="https://github.com/runoob-coder/eink_dither/raw/main/result/jarvisJudiceNinke_zigzag.png" width="200"/>   | <img src="https://github.com/runoob-coder/eink_dither/raw/main/result/jarvisJudiceNinke_hilbert.png" width="200"/>   |
| **Burkes**                          | <img src="https://github.com/runoob-coder/eink_dither/raw/main/result/burkes_raster.png" width="200"/>              | <img src="https://github.com/runoob-coder/eink_dither/raw/main/result/burkes_serpentine.png" width="200"/>              | <img src="https://github.com/runoob-coder/eink_dither/raw/main/result/burkes_zigzag.png" width="200"/>              | <img src="https://github.com/runoob-coder/eink_dither/raw/main/result/burkes_hilbert.png" width="200"/>              |
| **Sierra（Sierra-3）**                | <img src="https://github.com/runoob-coder/eink_dither/raw/main/result/sierra3_raster.png" width="200"/>             | <img src="https://github.com/runoob-coder/eink_dither/raw/main/result/sierra3_serpentine.png" width="200"/>             | <img src="https://github.com/runoob-coder/eink_dither/raw/main/result/sierra3_zigzag.png" width="200"/>             | <img src="https://github.com/runoob-coder/eink_dither/raw/main/result/sierra3_hilbert.png" width="200"/>             |
| **Two-Row Sierra（Sierra-2）**        | <img src="https://github.com/runoob-coder/eink_dither/raw/main/result/sierra2_raster.png" width="200"/>             | <img src="https://github.com/runoob-coder/eink_dither/raw/main/result/sierra2_serpentine.png" width="200"/>             | <img src="https://github.com/runoob-coder/eink_dither/raw/main/result/sierra2_zigzag.png" width="200"/>             | <img src="https://github.com/runoob-coder/eink_dither/raw/main/result/sierra2_hilbert.png" width="200"/>             |
| **Sierra Lite（Sierra-2-4-A）**       | <img src="https://github.com/runoob-coder/eink_dither/raw/main/result/sierraLite_raster.png" width="200"/>          | <img src="https://github.com/runoob-coder/eink_dither/raw/main/result/sierraLite_serpentine.png" width="200"/>          | <img src="https://github.com/runoob-coder/eink_dither/raw/main/result/sierraLite_zigzag.png" width="200"/>          | <img src="https://github.com/runoob-coder/eink_dither/raw/main/result/sierraLite_hilbert.png" width="200"/>          |

## 🔧 底层 API

如果需要更细粒度的控制，可直接使用 `ditherImage`（或仅有序抖动的辅助函数
`ditherImageBayer` / `ditherImageBlueNoise`），配合任意 `Quantizer`：

```dart
import 'package:image/image.dart' as img;
import 'package:eink_dither/eink_dither.dart';

final decoded = img.decodeImage(bytes)!;
final quantizer = EInkPaletteQuantizer.of(EInkPalette.spectra6);
final out = ditherImage(
  decoded,
  quantizer: quantizer,
  kernel: DitherKernel.floydSteinberg,
  scanOrder: DitherScanOrder.hilbert,
  patternSize: 1,
);
```

## ℹ️ 更多信息

- **仓库**: [github.com/runoob-coder/eink_dither](https://github.com/runoob-coder/eink_dither)
- **问题反馈**: [github.com/runoob-coder/eink_dither/issues](https://github.com/runoob-coder/eink_dither/issues)
- **示例应用**: `example/` 目录包含一个 Flutter 演示程序，可选择图像并实时调节调色板、抖动算法、
  扫描顺序、强度与图案尺寸。
- **贡献**: 欢迎提交 Pull Request 和 Issue！

## 💛 支持

如果 `eink_dither` 帮助了你，请考虑支持它，只需几秒即可帮助更多 Flutter 开发者发现此库。

- ⭐ [GitHub 上点星](https://github.com/runoob-coder/eink_dither)
- 👍 [pub.dev 上点赞](https://pub.dev/packages/eink_dither)

## ☕️ 请我喝咖啡

<a href="https://ko-fi.com/noob_coder" target="_blank">
  <img src="https://storage.ko-fi.com/cdn/kofi6.png" alt="Buy Me a Coffee at ko-fi.com" />
</a>

## 🙏 致谢

本库建立在图像数字抖动（dithering）与半调（halftoning）领域先驱者的研究之上。我们由衷感谢他们的奠基性贡献：

- **Floyd–Steinberg** —— Robert W. Floyd 与 Louis Steinberg（1976），经典误差扩散算法。
- **False Floyd–Steinberg（Heckbert）** —— Paul Heckbert，在其 1982 年 SIGGRAPH 课程讲义
  *Color Image Quantization for Frame Buffer Display* 中提出。
- **Jarvis–Judice–Ninke** —— J. F. Jarvis、C. N. Judice 与 W. H. Ninke（1976），贝尔实验室。
- **Stucki** —— Peter Stucki（1981），在 IBM 对 Jarvis 算法的优化改进。
- **Burkes** —— Daniel Burkes，Jarvis–Judice–Ninke 算法的简化 7 像素变体。
- **Atkinson** —— Bill Atkinson，为早期 Macintosh 的 MacPaint / HyperCard 所创。
- **Sierra（Sierra-3）、Two-Row Sierra（Sierra-2）与 Sierra Lite（Sierra-2-4-A）** —— Frankie Sierra
  （1989–1990），一组逐级缩小的卷积核，在质量与速度之间提供不同取舍。
- **Bayer（有序抖动）** —— Bryce E. Bayer（1973），亦以拜耳色彩滤波阵列闻名。
- **蓝噪声 / void-and-cluster** —— Robert A. Ulichney（1987、1993），*Digital Halftoning*，
  确立了蓝噪声抖动及 void-and-cluster 掩码生成方法。
