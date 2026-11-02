import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class PdfEngine {
  /// Converts one or multiple images into a multi-page PDF document
  static Future<File> imagesToPdf({
    required List<File> imageFiles,
    String? outputName,
  }) async {
    final pdf = pw.Document();

    for (final file in imageFiles) {
      if (!file.existsSync()) continue;
      final bytes = await file.readAsBytes();
      final image = pw.MemoryImage(bytes);

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(16),
          build: (pw.Context context) {
            return pw.Center(
              child: pw.Image(
                image,
                fit: pw.BoxFit.contain,
              ),
            );
          },
        ),
      );
    }

    final Uint8List pdfBytes = await pdf.save();
    final tempDir = await getTemporaryDirectory();
    final fileName = outputName ??
        (imageFiles.length == 1
            ? '${p.basenameWithoutExtension(imageFiles.first.path)}.pdf'
            : 'DropDial_Combined_${DateTime.now().millisecondsSinceEpoch}.pdf');

    final outFile = File(p.join(tempDir.path, fileName));
    await outFile.writeAsBytes(pdfBytes);
    return outFile;
  }

  /// Converts text content into a formatted PDF document
  static Future<File> textToPdf({
    required String text,
    required String title,
  }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) => [
          pw.Header(
            level: 0,
            child: pw.Text(
              title,
              style: pw.TextStyle(
                fontSize: 22,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Paragraph(
            text: text,
            style: const pw.TextStyle(
              fontSize: 12,
              lineSpacing: 1.5,
            ),
          ),
        ],
      ),
    );

    final Uint8List pdfBytes = await pdf.save();
    final tempDir = await getTemporaryDirectory();
    final timeStamp = DateTime.now().millisecondsSinceEpoch;
    final outFile = File(p.join(tempDir.path, '${title}_$timeStamp.pdf'));
    await outFile.writeAsBytes(pdfBytes);
    return outFile;
  }
}
