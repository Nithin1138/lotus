import 'package:flutter/material.dart';
import '../models/file_token.dart';
import '../models/petal_item.dart';
import '../models/wheel_mode.dart';
import '../../core/constants/app_colors.dart';

class ConversionCatalog {
  /// All known target format petals
  static const List<PetalItem> allFormats = [
    // Image Targets
    PetalItem(
      id: 'format:webp',
      label: 'WEBP',
      sublabel: 'Modern Web',
      icon: Icons.image_outlined,
      mode: WheelMode.formats,
      supportedCategories: [FileCategory.image],
      accentColor: AppColors.primaryCyan,
      badge: 'POPULAR',
    ),
    PetalItem(
      id: 'format:png',
      label: 'PNG',
      sublabel: 'Lossless',
      icon: Icons.image_search_rounded,
      mode: WheelMode.formats,
      supportedCategories: [FileCategory.image],
      accentColor: AppColors.accentBlue,
      badge: 'LOSSLESS',
    ),
    PetalItem(
      id: 'format:jpg',
      label: 'JPG',
      sublabel: 'Universal',
      icon: Icons.photo_camera_back_outlined,
      mode: WheelMode.formats,
      supportedCategories: [FileCategory.image],
      accentColor: AppColors.accentOrange,
    ),
    PetalItem(
      id: 'format:pdf',
      label: 'PDF',
      sublabel: 'Document',
      icon: Icons.picture_as_pdf_outlined,
      mode: WheelMode.formats,
      supportedCategories: [FileCategory.image, FileCategory.document, FileCategory.text],
      accentColor: AppColors.accentRed,
      badge: 'VECTOR',
    ),
    PetalItem(
      id: 'format:ico',
      label: 'ICO',
      sublabel: 'Favicon/App',
      icon: Icons.crop_square_rounded,
      mode: WheelMode.formats,
      supportedCategories: [FileCategory.image],
      accentColor: AppColors.accentAmber,
    ),
    PetalItem(
      id: 'format:bmp',
      label: 'BMP',
      sublabel: 'Bitmap',
      icon: Icons.grid_4x4_rounded,
      mode: WheelMode.formats,
      supportedCategories: [FileCategory.image],
      accentColor: AppColors.textSecondary,
    ),
    PetalItem(
      id: 'format:gif',
      label: 'GIF',
      sublabel: 'Animated',
      icon: Icons.gif_box_outlined,
      mode: WheelMode.formats,
      supportedCategories: [FileCategory.image, FileCategory.video],
      accentColor: AppColors.accentPurple,
    ),
    PetalItem(
      id: 'format:tiff',
      label: 'TIFF',
      sublabel: 'Print Quality',
      icon: Icons.print_outlined,
      mode: WheelMode.formats,
      supportedCategories: [FileCategory.image],
      accentColor: AppColors.accentGreen,
    ),

    // PDF / Doc Targets
    PetalItem(
      id: 'format:pdf_images',
      label: 'EXTRACT',
      sublabel: 'To Images',
      icon: Icons.collections_outlined,
      mode: WheelMode.formats,
      supportedCategories: [FileCategory.pdf],
      accentColor: AppColors.primaryCyan,
    ),
    PetalItem(
      id: 'format:pdf_txt',
      label: 'TXT',
      sublabel: 'Text Only',
      icon: Icons.text_snippet_outlined,
      mode: WheelMode.formats,
      supportedCategories: [FileCategory.pdf, FileCategory.document],
      accentColor: AppColors.accentAmber,
    ),

    // Audio Targets
    PetalItem(
      id: 'format:mp3',
      label: 'MP3',
      sublabel: 'MPEG Audio',
      icon: Icons.music_note_outlined,
      mode: WheelMode.formats,
      supportedCategories: [FileCategory.audio, FileCategory.video],
      accentColor: AppColors.accentGreen,
    ),
    PetalItem(
      id: 'format:wav',
      label: 'WAV',
      sublabel: 'PCM Lossless',
      icon: Icons.graphic_eq_rounded,
      mode: WheelMode.formats,
      supportedCategories: [FileCategory.audio],
      accentColor: AppColors.primaryCyan,
    ),
    PetalItem(
      id: 'format:m4a',
      label: 'M4A',
      sublabel: 'AAC Audio',
      icon: Icons.audiotrack_outlined,
      mode: WheelMode.formats,
      supportedCategories: [FileCategory.audio, FileCategory.video],
      accentColor: AppColors.accentOrange,
    ),

    // Video Targets
    PetalItem(
      id: 'format:mp4',
      label: 'MP4',
      sublabel: 'H.264 Video',
      icon: Icons.videocam_outlined,
      mode: WheelMode.formats,
      supportedCategories: [FileCategory.video],
      accentColor: AppColors.accentBlue,
    ),
    PetalItem(
      id: 'format:webm',
      label: 'WEBM',
      sublabel: 'VP9 Open Web',
      icon: Icons.video_collection_outlined,
      mode: WheelMode.formats,
      supportedCategories: [FileCategory.video],
      accentColor: AppColors.accentPurple,
    ),
  ];

  /// All known advanced tools petals
  static const List<PetalItem> allTools = [
    // Image & Media Tools
    PetalItem(
      id: 'tool:compress',
      label: 'COMPRESS',
      sublabel: 'Reduce Size',
      icon: Icons.compress_rounded,
      mode: WheelMode.tools,
      supportedCategories: [FileCategory.image, FileCategory.pdf, FileCategory.video],
      accentColor: AppColors.primaryCyan,
      badge: 'AUTO',
    ),
    PetalItem(
      id: 'tool:resize',
      label: 'RESIZE',
      sublabel: 'Dimensions',
      icon: Icons.aspect_ratio_rounded,
      mode: WheelMode.tools,
      supportedCategories: [FileCategory.image],
      accentColor: AppColors.accentOrange,
    ),
    PetalItem(
      id: 'tool:crop',
      label: 'CROP',
      sublabel: '1:1, 16:9, 9:16',
      icon: Icons.crop_rounded,
      mode: WheelMode.tools,
      supportedCategories: [FileCategory.image],
      accentColor: AppColors.accentPurple,
    ),
    PetalItem(
      id: 'tool:rotate',
      label: 'ROTATE',
      sublabel: '90° / 180° / Flip',
      icon: Icons.rotate_90_degrees_cw_rounded,
      mode: WheelMode.tools,
      supportedCategories: [FileCategory.image],
      accentColor: AppColors.accentGreen,
    ),
    PetalItem(
      id: 'tool:strip_exif',
      label: 'STRIP EXIF',
      sublabel: 'Privacy Wipe',
      icon: Icons.shield_outlined,
      mode: WheelMode.tools,
      supportedCategories: [FileCategory.image],
      accentColor: AppColors.accentGreen,
      badge: 'SAFE',
    ),
    PetalItem(
      id: 'tool:ocr',
      label: 'OCR TEXT',
      sublabel: 'Extract Text',
      icon: Icons.document_scanner_outlined,
      mode: WheelMode.tools,
      supportedCategories: [FileCategory.image, FileCategory.pdf],
      accentColor: AppColors.primaryCyan,
      badge: 'AI ML',
    ),
    PetalItem(
      id: 'tool:watermark',
      label: 'WATERMARK',
      sublabel: 'Text or Logo',
      icon: Icons.branding_watermark_outlined,
      mode: WheelMode.tools,
      supportedCategories: [FileCategory.image, FileCategory.pdf],
      accentColor: AppColors.accentAmber,
    ),
    PetalItem(
      id: 'tool:multi_to_pdf',
      label: 'MAKE PDF',
      sublabel: 'Combine Photos',
      icon: Icons.post_add_rounded,
      mode: WheelMode.tools,
      supportedCategories: [FileCategory.image],
      accentColor: AppColors.accentRed,
      badge: 'MULTI',
    ),
    PetalItem(
      id: 'tool:make_icon',
      label: 'MAKE ICON',
      sublabel: 'Favicon & App',
      icon: Icons.app_shortcut_rounded,
      mode: WheelMode.tools,
      supportedCategories: [FileCategory.image],
      accentColor: AppColors.accentBlue,
    ),
    PetalItem(
      id: 'tool:filter',
      label: 'FILTER',
      sublabel: 'B&W / Sepia / EV',
      icon: Icons.tune_rounded,
      mode: WheelMode.tools,
      supportedCategories: [FileCategory.image],
      accentColor: AppColors.accentPurple,
    ),
    PetalItem(
      id: 'tool:pdf_merge',
      label: 'MERGE PDF',
      sublabel: 'Join Documents',
      icon: Icons.merge_type_rounded,
      mode: WheelMode.tools,
      supportedCategories: [FileCategory.pdf],
      accentColor: AppColors.accentRed,
    ),
  ];

  /// Universal file actions petals
  static const List<PetalItem> allActions = [
    PetalItem(
      id: 'action:share',
      label: 'SHARE',
      sublabel: 'System Sheet',
      icon: Icons.share_rounded,
      mode: WheelMode.actions,
      accentColor: AppColors.primaryCyan,
      badge: 'QUICK',
    ),
    PetalItem(
      id: 'action:save_downloads',
      label: 'SAVE',
      sublabel: 'To Downloads',
      icon: Icons.download_rounded,
      mode: WheelMode.actions,
      accentColor: AppColors.accentGreen,
    ),
    PetalItem(
      id: 'action:copy_file',
      label: 'COPY FILE',
      sublabel: 'To Clipboard',
      icon: Icons.copy_rounded,
      mode: WheelMode.actions,
      accentColor: AppColors.accentBlue,
    ),
    PetalItem(
      id: 'action:copy_path',
      label: 'COPY PATH',
      sublabel: 'Full File URI',
      icon: Icons.link_rounded,
      mode: WheelMode.actions,
      accentColor: AppColors.textSecondary,
    ),
    PetalItem(
      id: 'action:info',
      label: 'DETAILS',
      sublabel: 'Metadata & EXIF',
      icon: Icons.info_outline_rounded,
      mode: WheelMode.actions,
      accentColor: AppColors.accentAmber,
    ),
    PetalItem(
      id: 'action:preview',
      label: 'PREVIEW',
      sublabel: 'Full Screen',
      icon: Icons.visibility_outlined,
      mode: WheelMode.actions,
      accentColor: AppColors.accentPurple,
    ),
  ];

  /// Context-aware filtering based on active file category
  static List<PetalItem> getPetalsFor({
    required WheelMode mode,
    FileCategory? category,
    String? currentExtension,
  }) {
    final cat = category ?? FileCategory.image;
    final currentExt = currentExtension?.toLowerCase().replaceAll('.', '');

    switch (mode) {
      case WheelMode.formats:
        final matching = allFormats.where((p) => p.supportsCategory(cat)).toList();
        // Move current format to the end or filter it, keep targets in front
        matching.sort((a, b) {
          final aIsCurrent = a.id == 'format:$currentExt';
          final bIsCurrent = b.id == 'format:$currentExt';
          if (aIsCurrent) return 1;
          if (bIsCurrent) return -1;
          return 0;
        });
        return matching;

      case WheelMode.tools:
        return allTools.where((p) => p.supportsCategory(cat)).toList();

      case WheelMode.actions:
        return allActions;
    }
  }
}
