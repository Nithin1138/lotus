import 'dart:io';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../domain/models/file_token.dart';
import '../domain/models/petal_item.dart';
import 'image_engine.dart';
import 'ocr_engine.dart';
import 'pdf_engine.dart';

class ExecutionResult {
  final bool success;
  final String message;
  final File? outputFile;
  final String? extractedText;
  final int? outputSizeBytes;
  final String? error;

  ExecutionResult({
    required this.success,
    required this.message,
    this.outputFile,
    this.extractedText,
    this.outputSizeBytes,
    this.error,
  });

  String get formattedOutputSize {
    final size = outputSizeBytes ?? (outputFile?.existsSync() == true ? outputFile!.lengthSync() : 0);
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class ConversionOrchestrator {
  /// Execute the operation requested by petal on the input file token
  static Future<ExecutionResult> execute({
    required PetalItem petal,
    required FileToken fileToken,
    Map<String, dynamic>? customParams,
  }) async {
    final inputFile = File(fileToken.path);
    if (!inputFile.existsSync()) {
      return ExecutionResult(
        success: false,
        message: 'Source file not found at ${fileToken.path}',
        error: 'File does not exist',
      );
    }

    try {
      // 1. Format Conversions
      if (petal.id.startsWith('format:')) {
        final targetFormat = petal.id.replaceFirst('format:', '');

        if (targetFormat == 'pdf') {
          final outFile = await PdfEngine.imagesToPdf(
            imageFiles: [inputFile],
            outputName: '${p.basenameWithoutExtension(fileToken.path)}.pdf',
          );
          return ExecutionResult(
            success: true,
            message: 'Converted to PDF',
            outputFile: outFile,
          );
        }

        final outFile = await ImageEngine.convertFormat(
          inputFile: inputFile,
          targetFormat: targetFormat,
          quality: customParams?['quality'] ?? 90,
        );
        return ExecutionResult(
          success: true,
          message: 'Converted to ${targetFormat.toUpperCase()}',
          outputFile: outFile,
        );
      }

      // 2. Tools
      if (petal.id.startsWith('tool:')) {
        switch (petal.id) {
          case 'tool:compress':
            final targetKb = customParams?['targetSizeKb'] ?? 500;
            final outFile = await ImageEngine.compressImage(
              inputFile: inputFile,
              targetSizeKb: targetKb,
            );
            return ExecutionResult(
              success: true,
              message: 'Compressed successfully',
              outputFile: outFile,
            );

          case 'tool:resize':
            final outFile = await ImageEngine.resizeImage(
              inputFile: inputFile,
              scalePercentage: customParams?['scalePercentage'] ?? 50,
            );
            return ExecutionResult(
              success: true,
              message: 'Resized image',
              outputFile: outFile,
            );

          case 'tool:crop':
            final outFile = await ImageEngine.cropAndRotate(
              inputFile: inputFile,
              aspectRatio: customParams?['aspectRatio'] ?? '1:1',
            );
            return ExecutionResult(
              success: true,
              message: 'Cropped to 1:1 Square',
              outputFile: outFile,
            );

          case 'tool:rotate':
            final outFile = await ImageEngine.cropAndRotate(
              inputFile: inputFile,
              rotationDegrees: 90,
            );
            return ExecutionResult(
              success: true,
              message: 'Rotated 90° Clockwise',
              outputFile: outFile,
            );

          case 'tool:strip_exif':
            final outFile = await ImageEngine.stripExif(inputFile: inputFile);
            return ExecutionResult(
              success: true,
              message: 'EXIF metadata & GPS coordinates wiped',
              outputFile: outFile,
            );

          case 'tool:ocr':
            final ocrRes = await OcrEngine.recognizeText(inputFile);
            // Copy directly to clipboard for instant utility
            await Clipboard.setData(ClipboardData(text: ocrRes.fullText));
            return ExecutionResult(
              success: true,
              message: 'Extracted ${ocrRes.lineCount} lines (Copied to Clipboard)',
              extractedText: ocrRes.fullText,
            );

          case 'tool:watermark':
            final outFile = await ImageEngine.applyWatermark(inputFile: inputFile);
            return ExecutionResult(
              success: true,
              message: 'Watermark badge applied',
              outputFile: outFile,
            );

          case 'tool:multi_to_pdf':
            final filesToCombine = fileToken.batchPaths.isNotEmpty
                ? fileToken.batchPaths.map((path) => File(path)).toList()
                : [inputFile];
            final outFile = await PdfEngine.imagesToPdf(imageFiles: filesToCombine);
            return ExecutionResult(
              success: true,
              message: 'Created PDF from ${filesToCombine.length} images',
              outputFile: outFile,
            );

          case 'tool:make_icon':
            final outFile = await ImageEngine.convertFormat(
              inputFile: inputFile,
              targetFormat: 'ico',
            );
            return ExecutionResult(
              success: true,
              message: 'Generated Windows & Favicon ICO',
              outputFile: outFile,
            );

          case 'tool:filter':
            final outFile = await ImageEngine.applyFilter(
              inputFile: inputFile,
              filterType: customParams?['filter'] ?? 'grayscale',
            );
            return ExecutionResult(
              success: true,
              message: 'Filter applied',
              outputFile: outFile,
            );

          default:
            return ExecutionResult(
              success: false,
              message: 'Tool ${petal.label} not implemented yet',
            );
        }
      }

      // 3. Actions
      if (petal.id.startsWith('action:')) {
        switch (petal.id) {
          case 'action:share':
            await SharePlus.instance.share(
              ShareParams(
                files: [XFile(fileToken.path)],
                text: 'Sharing ${fileToken.name} via DropDial',
              ),
            );
            return ExecutionResult(
              success: true,
              message: 'Opened System Share Sheet',
            );

          case 'action:copy_path':
            await Clipboard.setData(ClipboardData(text: fileToken.path));
            return ExecutionResult(
              success: true,
              message: 'Path copied to clipboard: ${fileToken.path}',
            );

          case 'action:copy_file':
            // Copies file path or file URI to clipboard
            await Clipboard.setData(ClipboardData(text: fileToken.path));
            return ExecutionResult(
              success: true,
              message: 'File reference copied to clipboard',
            );

          case 'action:save_downloads':
            final downloadsDir = Directory('/storage/emulated/0/Download');
            Directory targetDir;
            if (downloadsDir.existsSync()) {
              targetDir = downloadsDir;
            } else {
              targetDir = (await getExternalStorageDirectory()) ?? (await getApplicationDocumentsDirectory());
            }

            final destPath = p.join(targetDir.path, fileToken.name);
            await inputFile.copy(destPath);
            return ExecutionResult(
              success: true,
              message: 'Saved to ${p.basename(targetDir.path)}/${fileToken.name}',
              outputFile: File(destPath),
            );

          case 'action:preview':
            await OpenFilex.open(fileToken.path);
            return ExecutionResult(
              success: true,
              message: 'Opened in default system viewer',
            );

          case 'action:info':
            return ExecutionResult(
              success: true,
              message: '${fileToken.name} • ${fileToken.formattedSize} • ${fileToken.mimeType}',
            );

          default:
            return ExecutionResult(
              success: false,
              message: 'Action ${petal.label} not recognized',
            );
        }
      }

      return ExecutionResult(
        success: false,
        message: 'Unknown operation ${petal.id}',
      );
    } catch (e, st) {
      return ExecutionResult(
        success: false,
        message: 'Operation failed: $e',
        error: '$e\n$st',
      );
    }
  }
}
