import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;

enum FileCategory {
  image,
  document,
  pdf,
  video,
  audio,
  archive,
  text,
  unknown,
}

class FileToken {
  final String path;
  final String name;
  final String extension;
  final int sizeBytes;
  final String mimeType;
  final FileCategory category;
  final Uint8List? thumbnailBytes;
  final int? width;
  final int? height;
  final int? pageCount;
  final List<String> batchPaths;

  FileToken({
    required this.path,
    required this.name,
    required this.extension,
    required this.sizeBytes,
    required this.mimeType,
    required this.category,
    this.thumbnailBytes,
    this.width,
    this.height,
    this.pageCount,
    this.batchPaths = const [],
  });

  bool get isBatch => batchPaths.length > 1;
  int get count => isBatch ? batchPaths.length : 1;

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    if (sizeBytes < 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String get formattedDimensions {
    if (width != null && height != null) {
      return '${width}x$height';
    }
    if (pageCount != null) {
      return '$pageCount ${pageCount == 1 ? "page" : "pages"}';
    }
    return extension.toUpperCase();
  }

  static FileCategory categorize(String ext) {
    final cleanExt = ext.replaceAll('.', '').toLowerCase();
    switch (cleanExt) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'webp':
      case 'bmp':
      case 'gif':
      case 'ico':
      case 'svg':
      case 'tiff':
      case 'heic':
      case 'heif':
      case 'avif':
        return FileCategory.image;
      case 'pdf':
        return FileCategory.pdf;
      case 'doc':
      case 'docx':
      case 'ppt':
      case 'pptx':
      case 'xls':
      case 'xlsx':
      case 'odt':
      case 'ods':
        return FileCategory.document;
      case 'mp4':
      case 'mov':
      case 'avi':
      case 'mkv':
      case 'webm':
      case 'flv':
      case '3gp':
        return FileCategory.video;
      case 'mp3':
      case 'wav':
      case 'm4a':
      case 'aac':
      case 'ogg':
      case 'flac':
      case 'wma':
        return FileCategory.audio;
      case 'zip':
      case 'tar':
      case 'gz':
      case '7z':
      case 'rar':
        return FileCategory.archive;
      case 'txt':
      case 'md':
      case 'json':
      case 'xml':
      case 'csv':
      case 'html':
      case 'css':
      case 'js':
      case 'dart':
        return FileCategory.text;
      default:
        return FileCategory.unknown;
    }
  }

  factory FileToken.fromFile(File file, {Uint8List? thumbnailBytes}) {
    final filePath = file.path;
    final fileName = p.basename(filePath);
    final ext = p.extension(filePath).replaceAll('.', '').toLowerCase();
    final stat = file.existsSync() ? file.statSync() : null;
    final size = stat?.size ?? 0;
    final cat = categorize(ext);

    return FileToken(
      path: filePath,
      name: fileName,
      extension: ext,
      sizeBytes: size,
      mimeType: _guessMimeType(ext),
      category: cat,
      thumbnailBytes: thumbnailBytes,
      batchPaths: [filePath],
    );
  }

  FileToken copyWith({
    String? path,
    String? name,
    String? extension,
    int? sizeBytes,
    String? mimeType,
    FileCategory? category,
    Uint8List? thumbnailBytes,
    int? width,
    int? height,
    int? pageCount,
    List<String>? batchPaths,
  }) {
    return FileToken(
      path: path ?? this.path,
      name: name ?? this.name,
      extension: extension ?? this.extension,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      mimeType: mimeType ?? this.mimeType,
      category: category ?? this.category,
      thumbnailBytes: thumbnailBytes ?? this.thumbnailBytes,
      width: width ?? this.width,
      height: height ?? this.height,
      pageCount: pageCount ?? this.pageCount,
      batchPaths: batchPaths ?? this.batchPaths,
    );
  }

  static String _guessMimeType(String ext) {
    switch (ext.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'bmp':
        return 'image/bmp';
      case 'svg':
        return 'image/svg+xml';
      case 'pdf':
        return 'application/pdf';
      case 'mp4':
        return 'video/mp4';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'txt':
        return 'text/plain';
      case 'json':
        return 'application/json';
      case 'zip':
        return 'application/zip';
      default:
        return 'application/octet-stream';
    }
  }
}
