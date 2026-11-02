import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrResult {
  final String fullText;
  final int lineCount;
  final int blockCount;
  final List<String> lines;

  OcrResult({
    required this.fullText,
    required this.lineCount,
    required this.blockCount,
    required this.lines,
  });
}

class OcrEngine {
  static final TextRecognizer _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  /// Performs offline on-device text recognition on an image file
  static Future<OcrResult> recognizeText(File imageFile) async {
    final inputImage = InputImage.fromFile(imageFile);
    final RecognizedText recognizedText = await _recognizer.processImage(inputImage);

    final List<String> allLines = [];
    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        allLines.add(line.text);
      }
    }

    return OcrResult(
      fullText: recognizedText.text,
      lineCount: allLines.length,
      blockCount: recognizedText.blocks.length,
      lines: allLines,
    );
  }

  static void dispose() {
    _recognizer.close();
  }
}

