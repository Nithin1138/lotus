import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:dropdial_flutter/engine/image_engine.dart';
import 'package:dropdial_flutter/engine/pdf_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File sampleImageFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dropdial_test_');

    const MethodChannel channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
      return tempDir.path;
    });

    // Generate a valid 200x200 test PNG image
    final sampleImg = img.Image(width: 200, height: 200);
    img.fill(sampleImg, color: img.ColorRgb8(0, 229, 255));
    final pngBytes = img.encodePng(sampleImg);

    sampleImageFile = File('${tempDir.path}/sample.png');
    await sampleImageFile.writeAsBytes(pngBytes);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Offline Local Engine Tests', () {
    test('ImageEngine converts PNG to JPG', () async {
      final jpgFile = await ImageEngine.convertFormat(
        inputFile: sampleImageFile,
        targetFormat: 'jpg',
        quality: 85,
      );
      expect(jpgFile.existsSync(), isTrue);
      expect(jpgFile.path.endsWith('.jpg'), isTrue);
      expect(jpgFile.lengthSync(), greaterThan(0));
    });

    test('ImageEngine resizes image', () async {
      final resizedFile = await ImageEngine.resizeImage(
        inputFile: sampleImageFile,
        scalePercentage: 50,
      );
      expect(resizedFile.existsSync(), isTrue);
      final decoded = img.decodeImage(await resizedFile.readAsBytes());
      expect(decoded, isNotNull);
      expect(decoded!.width, equals(100));
      expect(decoded.height, equals(100));
    });

    test('ImageEngine crops image to 1:1', () async {
      final cropped = await ImageEngine.cropAndRotate(
        inputFile: sampleImageFile,
        aspectRatio: '1:1',
      );
      expect(cropped.existsSync(), isTrue);
      expect(cropped.lengthSync(), greaterThan(0));
    });

    test('ImageEngine strips EXIF', () async {
      final stripped = await ImageEngine.stripExif(inputFile: sampleImageFile);
      expect(stripped.existsSync(), isTrue);
      expect(stripped.lengthSync(), greaterThan(0));
    });

    test('PdfEngine creates PDF from image', () async {
      final pdfFile = await PdfEngine.imagesToPdf(imageFiles: [sampleImageFile]);
      expect(pdfFile.existsSync(), isTrue);
      expect(pdfFile.path.endsWith('.pdf'), isTrue);
      expect(pdfFile.lengthSync(), greaterThan(0));
    });
  });
}
