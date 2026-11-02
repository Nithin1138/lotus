import 'package:flutter_test/flutter_test.dart';
import 'package:dropdial_flutter/core/constants/wheel_constants.dart';
import 'package:dropdial_flutter/domain/converters/conversion_catalog.dart';
import 'package:dropdial_flutter/domain/models/file_token.dart';
import 'package:dropdial_flutter/domain/models/wheel_mode.dart';

void main() {
  group('DropDial Mobile Geometry & Categorization Tests', () {
    test('Sector angle partitions semicircle into 6 active petals', () {
      expect(WheelConstants.petalSectorAngle, closeTo(3.14159 / 6, 0.001));
      expect(WheelConstants.innerRadius, equals(74.0));
      expect(WheelConstants.outerRadius, equals(185.0));
    });

    test('FileToken categorizes extensions properly', () {
      expect(FileToken.categorize('png'), equals(FileCategory.image));
      expect(FileToken.categorize('jpg'), equals(FileCategory.image));
      expect(FileToken.categorize('webp'), equals(FileCategory.image));
      expect(FileToken.categorize('pdf'), equals(FileCategory.pdf));
      expect(FileToken.categorize('mp4'), equals(FileCategory.video));
      expect(FileToken.categorize('mp3'), equals(FileCategory.audio));
      expect(FileToken.categorize('zip'), equals(FileCategory.archive));
      expect(FileToken.categorize('txt'), equals(FileCategory.text));
    });

    test('ConversionCatalog returns contextual petals for Image', () {
      final petals = ConversionCatalog.getPetalsFor(
        mode: WheelMode.formats,
        category: FileCategory.image,
        currentExtension: 'png',
      );
      expect(petals.isNotEmpty, isTrue);
      // Ensure target formats like WEBP, JPG, PDF are included
      final ids = petals.map((p) => p.id).toList();
      expect(ids.contains('format:webp'), isTrue);
      expect(ids.contains('format:jpg'), isTrue);
      expect(ids.contains('format:pdf'), isTrue);
    });

    test('ConversionCatalog returns tools petals for Image', () {
      final tools = ConversionCatalog.getPetalsFor(
        mode: WheelMode.tools,
        category: FileCategory.image,
      );
      expect(tools.isNotEmpty, isTrue);
      final ids = tools.map((p) => p.id).toList();
      expect(ids.contains('tool:compress'), isTrue);
      expect(ids.contains('tool:resize'), isTrue);
      expect(ids.contains('tool:crop'), isTrue);
      expect(ids.contains('tool:strip_exif'), isTrue);
      expect(ids.contains('tool:ocr'), isTrue);
    });

    test('ConversionCatalog returns universal actions', () {
      final actions = ConversionCatalog.getPetalsFor(
        mode: WheelMode.actions,
      );
      expect(actions.isNotEmpty, isTrue);
      final ids = actions.map((p) => p.id).toList();
      expect(ids.contains('action:share'), isTrue);
      expect(ids.contains('action:copy_path'), isTrue);
      expect(ids.contains('action:save_downloads'), isTrue);
    });
  });
}

