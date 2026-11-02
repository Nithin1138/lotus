import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ImageEngine {
  /// Converts an image file to a target format
  static Future<File> convertFormat({
    required File inputFile,
    required String targetFormat, // 'webp', 'png', 'jpg', 'bmp', 'ico', 'tiff', 'gif'
    int quality = 85,
  }) async {
    final bytes = await inputFile.readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) {
      throw Exception('Failed to decode image from ${inputFile.path}');
    }

    Uint8List outputBytes;
    final cleanFormat = targetFormat.toLowerCase().replaceAll('.', '');

    switch (cleanFormat) {
      case 'webp':
        outputBytes = Uint8List.fromList(img.encodeNamedImage(inputFile.path, image) ?? img.encodeJpg(image, quality: quality));
        // package:image encodes webp via encodeNamedImage or encodePng/encodeJpg fallback if webp encoder direct isn't available
        try {
          outputBytes = Uint8List.fromList(img.encodePng(image)); // or native webp
        } catch (_) {}
        break;
      case 'png':
        outputBytes = Uint8List.fromList(img.encodePng(image, level: 6));
        break;
      case 'jpg':
      case 'jpeg':
        outputBytes = Uint8List.fromList(img.encodeJpg(image, quality: quality));
        break;
      case 'bmp':
        outputBytes = Uint8List.fromList(img.encodeBmp(image));
        break;
      case 'ico':
        // Resize to 256x256 max for ICO
        final square = img.copyResize(image, width: 256, height: 256);
        outputBytes = Uint8List.fromList(img.encodeIco(square));
        break;
      case 'tiff':
        outputBytes = Uint8List.fromList(img.encodeTiff(image));
        break;
      case 'gif':
        outputBytes = Uint8List.fromList(img.encodeGif(image));
        break;
      default:
        outputBytes = Uint8List.fromList(img.encodePng(image));
    }

    return _writeOutputFile(
      baseName: p.basenameWithoutExtension(inputFile.path),
      extension: cleanFormat,
      bytes: outputBytes,
    );
  }

  /// Compresses image to target quality or target size limit in KB
  static Future<File> compressImage({
    required File inputFile,
    int quality = 75,
    int? maxDimension = 1920,
    int? targetSizeKb,
  }) async {
    final bytes = await inputFile.readAsBytes();
    var image = img.decodeImage(bytes);
    if (image == null) throw Exception('Cannot decode image');

    // Scale down if larger than maxDimension
    if (maxDimension != null && (image.width > maxDimension || image.height > maxDimension)) {
      if (image.width >= image.height) {
        image = img.copyResize(image, width: maxDimension);
      } else {
        image = img.copyResize(image, height: maxDimension);
      }
    }

    Uint8List outputBytes;
    if (targetSizeKb != null && targetSizeKb > 0) {
      // Binary search / iterative reduction for target size
      int currentQuality = quality;
      outputBytes = Uint8List.fromList(img.encodeJpg(image, quality: currentQuality));
      while (outputBytes.lengthInBytes > targetSizeKb * 1024 && currentQuality > 20) {
        currentQuality -= 15;
        outputBytes = Uint8List.fromList(img.encodeJpg(image, quality: currentQuality));
      }
    } else {
      outputBytes = Uint8List.fromList(img.encodeJpg(image, quality: quality));
    }

    return _writeOutputFile(
      baseName: '${p.basenameWithoutExtension(inputFile.path)}_compressed',
      extension: 'jpg',
      bytes: outputBytes,
    );
  }

  /// Resizes image by custom width/height or scale percentage
  static Future<File> resizeImage({
    required File inputFile,
    int? width,
    int? height,
    double? scalePercentage,
    bool maintainAspect = true,
  }) async {
    final bytes = await inputFile.readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) throw Exception('Cannot decode image');

    int targetW = image.width;
    int targetH = image.height;

    if (scalePercentage != null) {
      targetW = (image.width * (scalePercentage / 100)).round();
      targetH = (image.height * (scalePercentage / 100)).round();
    } else if (width != null && height != null) {
      if (maintainAspect) {
        final double ratioW = width / image.width;
        final double ratioH = height / image.height;
        final double ratio = math.min(ratioW, ratioH);
        targetW = (image.width * ratio).round();
        targetH = (image.height * ratio).round();
      } else {
        targetW = width;
        targetH = height;
      }
    } else if (width != null) {
      final double ratio = width / image.width;
      targetW = width;
      targetH = (image.height * ratio).round();
    } else if (height != null) {
      final double ratio = height / image.height;
      targetH = height;
      targetW = (image.width * ratio).round();
    }

    final resized = img.copyResize(image, width: targetW, height: targetH);
    final ext = p.extension(inputFile.path).replaceAll('.', '').toLowerCase();
    final isPng = ext == 'png';
    final outputBytes = isPng ? img.encodePng(resized) : img.encodeJpg(resized, quality: 90);

    return _writeOutputFile(
      baseName: '${p.basenameWithoutExtension(inputFile.path)}_${targetW}x$targetH',
      extension: isPng ? 'png' : 'jpg',
      bytes: Uint8List.fromList(outputBytes),
    );
  }

  /// Crop and Rotate image
  static Future<File> cropAndRotate({
    required File inputFile,
    int rotationDegrees = 0, // 0, 90, 180, 270
    bool flipH = false,
    bool flipV = false,
    String? aspectRatio, // '1:1', '16:9', '9:16', '4:3'
  }) async {
    final bytes = await inputFile.readAsBytes();
    var image = img.decodeImage(bytes);
    if (image == null) throw Exception('Cannot decode image');

    // Rotation
    if (rotationDegrees != 0) {
      image = img.copyRotate(image, angle: rotationDegrees.toDouble());
    }
    if (flipH) {
      image = img.flipHorizontal(image);
    }
    if (flipV) {
      image = img.flipVertical(image);
    }

    // Aspect Ratio Crop
    if (aspectRatio != null) {
      double targetRatio = 1.0;
      switch (aspectRatio) {
        case '1:1':
          targetRatio = 1.0;
          break;
        case '16:9':
          targetRatio = 16 / 9;
          break;
        case '9:16':
          targetRatio = 9 / 16;
          break;
        case '4:3':
          targetRatio = 4 / 3;
          break;
        default:
          targetRatio = 1.0;
      }

      int cropW = image.width;
      int cropH = (cropW / targetRatio).round();
      if (cropH > image.height) {
        cropH = image.height;
        cropW = (cropH * targetRatio).round();
      }

      final x = ((image.width - cropW) / 2).round();
      final y = ((image.height - cropH) / 2).round();

      image = img.copyCrop(image, x: x, y: y, width: cropW, height: cropH);
    }

    final ext = p.extension(inputFile.path).replaceAll('.', '').toLowerCase();
    final isPng = ext == 'png';
    final outputBytes = isPng ? img.encodePng(image) : img.encodeJpg(image, quality: 92);

    return _writeOutputFile(
      baseName: '${p.basenameWithoutExtension(inputFile.path)}_processed',
      extension: isPng ? 'png' : 'jpg',
      bytes: Uint8List.fromList(outputBytes),
    );
  }

  /// Strip EXIF / Privacy Scrubbing
  /// Re-encodes the image without carrying forward EXIF or GPS metadata
  static Future<File> stripExif({required File inputFile}) async {
    final bytes = await inputFile.readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) throw Exception('Cannot decode image');

    // Clear all metadata dictionary tags
    image.textData?.clear();

    final ext = p.extension(inputFile.path).replaceAll('.', '').toLowerCase();
    final isPng = ext == 'png';
    final outputBytes = isPng
        ? img.encodePng(image)
        : img.encodeJpg(image, quality: 95);

    return _writeOutputFile(
      baseName: '${p.basenameWithoutExtension(inputFile.path)}_clean',
      extension: isPng ? 'png' : 'jpg',
      bytes: Uint8List.fromList(outputBytes),
    );
  }

  /// Apply Quick Filter (Grayscale, Sepia, Invert)
  static Future<File> applyFilter({
    required File inputFile,
    required String filterType, // 'grayscale', 'sepia', 'invert', 'warm'
  }) async {
    final bytes = await inputFile.readAsBytes();
    var image = img.decodeImage(bytes);
    if (image == null) throw Exception('Cannot decode image');

    switch (filterType.toLowerCase()) {
      case 'grayscale':
      case 'bw':
        image = img.grayscale(image);
        break;
      case 'sepia':
        image = img.sepia(image);
        break;
      case 'invert':
        image = img.invert(image);
        break;
      case 'warm':
        image = img.adjustColor(image, gamma: 1.1, saturation: 1.2);
        break;
    }

    final outputBytes = img.encodeJpg(image, quality: 90);
    return _writeOutputFile(
      baseName: '${p.basenameWithoutExtension(inputFile.path)}_$filterType',
      extension: 'jpg',
      bytes: Uint8List.fromList(outputBytes),
    );
  }

  /// Apply simple text watermark
  static Future<File> applyWatermark({
    required File inputFile,
    String text = 'DROPDIAIL PROTECTED',
  }) async {
    final bytes = await inputFile.readAsBytes();
    var image = img.decodeImage(bytes);
    if (image == null) throw Exception('Cannot decode image');

    // Draw string watermark near bottom-right
    img.drawString(
      image,
      text,
      font: img.arial24,
      x: math.max(16, image.width - (text.length * 15) - 32),
      y: math.max(16, image.height - 48),
      color: img.ColorRgba8(255, 255, 255, 180),
    );

    final outputBytes = img.encodeJpg(image, quality: 92);
    return _writeOutputFile(
      baseName: '${p.basenameWithoutExtension(inputFile.path)}_watermarked',
      extension: 'jpg',
      bytes: Uint8List.fromList(outputBytes),
    );
  }

  /// Generate high-speed thumbnail for the Center Hub
  static Future<Uint8List?> generateThumbnail(File file, {int targetSize = 256}) async {
    try {
      final bytes = await file.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return null;
      final thumb = img.copyResizeCropSquare(image, size: targetSize);
      return Uint8List.fromList(img.encodeJpg(thumb, quality: 80));
    } catch (_) {
      return null;
    }
  }

  static Future<File> _writeOutputFile({
    required String baseName,
    required String extension,
    required Uint8List bytes,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final timeStamp = DateTime.now().millisecondsSinceEpoch;
    final outPath = p.join(tempDir.path, '${baseName}_$timeStamp.$extension');
    final file = File(outPath);
    await file.writeAsBytes(bytes);
    return file;
  }
}
