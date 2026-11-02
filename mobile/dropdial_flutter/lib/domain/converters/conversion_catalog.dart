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
      icon: Icons.language_rounded,
      mode: WheelMode.formats,
      supportedCategories: [FileCategory.image],
      accentColor: AppColors.dropdialOrange,
      badge: 'FAST',
    ),
    PetalItem(
      id: 'format:png',
      label: 'PNG',
      sublabel: 'Lossless',
      icon: Icons.image_rounded,
      mode: WheelMode.formats,
      supportedCategories: [FileCategory.image],
      accentColor: AppColors.primaryCyan,
      badge: 'LOSSLESS',
    ),
    PetalItem(
      id: 'format:jpg',
      label: 'JPG',
      sublabel: 'Universal',
      icon: Icons.photo_camera_rounded,
      mode: WheelMode.formats,
      supportedCategories: [FileCategory.image],
      accentColor: AppColors.accentAmber,
    ),
    PetalItem(
      id: 'format:pdf',
      label: 'PDF',
      sublabel: 'Document',
      icon: Icons.picture_as_pdf_rounded,
      mode: WheelMode.formats,
      supportedCategories: [FileCategory.image, FileCategory.document, FileCategory.text],
      accentColor: AppColors.accentRed,
      badge: 'PAGES',
    ),
    PetalItem(
      id: 'format:ico',
      label: 'ICO',
      sublabel: 'Favicon/App',
      icon: Icons.app_shortcut_rounded,
      mode: WheelMode.formats,
      supportedCategories: [FileCategory.image],
      accentColor: AppColors.accentPurple,
    ),
    PetalItem(
      id: 'format:bmp',
      label: 'BMP',
      sublabel: 'Raw Bitmap',
      icon: Icons.grid_view_rounded,
      mode: WheelMode.formats,
      supportedCategories: [FileCategory.image],
      accentColor: AppColors.textSecondary,
    ),
    PetalItem(
      id: 'format:gif',
      label: 'GIF',
      sublabel: 'Animation',
      icon: Icons.gif_box_rounded,
      mode: WheelMode.formats,
      supportedCategories: [FileCategory.image, FileCategory.video],
      accentColor: AppColors.accentPurple,
    ),
    PetalItem(
      id: 'format:tiff',
      label: 'TIFF',
      sublabel: 'Print Quality',
      icon: Icons.print_rounded,
      mode: WheelMode.formats,
      supportedCategories: [FileCategory.image],
      accentColor: AppColors.accentGreen,
    ),

    // PDF / Doc Targets
    PetalItem(
      id: 'format:pdf_images',
      label: 'EXTRACT',
      sublabel: 'To Images',
      icon: Icons.photo_library_rounded,
      mode: WheelMode.formats,
      supportedCategories: [FileCategory.pdf],
      accentColor: AppColors.dropdialOrange,
    ),
    PetalItem(
      id: 'format:pdf_txt',
      label: 'TXT',
      sublabel: 'Plain Text',
      icon: Icons.text_snippet_rounded,
      mode: WheelMode.formats,
      supportedCategories: [FileCategory.pdf, FileCategory.document],
      accentColor: AppColors.accentAmber,
    ),

    // Audio Targets
    PetalItem(
      id: 'format:mp3',
      label: 'MP3',
      sublabel: 'MPEG Audio',
      icon: Icons.music_note_rounded,
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
      icon: Icons.audiotrack_rounded,
      mode: WheelMode.formats,
      supportedCategories: [FileCategory.audio, FileCategory.video],
      accentColor: AppColors.dropdialOrange,
    ),

    // Video Targets
    PetalItem(
      id: 'format:mp4',
      label: 'MP4',
      sublabel: 'H.264 Video',
      icon: Icons.movie_creation_rounded,
      mode: WheelMode.formats,
      supportedCategories: [FileCategory.video],
      accentColor: AppColors.accentBlue,
    ),
    PetalItem(
      id: 'format:webm',
      label: 'WEBM',
      sublabel: 'VP9 Open Web',
      icon: Icons.smart_display_rounded,
      mode: WheelMode.formats,
      supportedCategories: [FileCategory.video],
      accentColor: AppColors.accentPurple,
    ),
  ];

  /// All known advanced tools petals (matching macOS ToolWindow palette)
  static const List<PetalItem> allTools = [
    PetalItem(
      id: 'tool:compress',
      label: 'Compress',
      sublabel: 'Reduce Size',
      icon: Icons.arrow_downward_rounded,
      mode: WheelMode.tools,
      supportedCategories: [FileCategory.image, FileCategory.pdf, FileCategory.video],
      accentColor: AppColors.dropdialOrange,
      badge: 'AUTO',
    ),
    PetalItem(
      id: 'tool:resize',
      label: 'Resize',
      sublabel: 'Dimensions',
      icon: Icons.open_in_full_rounded,
      mode: WheelMode.tools,
      supportedCategories: [FileCategory.image],
      accentColor: AppColors.primaryCyan,
    ),
    PetalItem(
      id: 'tool:crop',
      label: 'Crop',
      sublabel: '1:1, 16:9, 9:16',
      icon: Icons.crop_rounded,
      mode: WheelMode.tools,
      supportedCategories: [FileCategory.image],
      accentColor: AppColors.accentPurple,
    ),
    PetalItem(
      id: 'tool:rotate',
      label: 'Rotate',
      sublabel: '90° / 180° / Flip',
      icon: Icons.rotate_right_rounded,
      mode: WheelMode.tools,
      supportedCategories: [FileCategory.image],
      accentColor: AppColors.accentGreen,
    ),
    PetalItem(
      id: 'tool:strip_exif',
      label: 'Strip EXIF',
      sublabel: 'Privacy Wipe',
      icon: Icons.shield_rounded,
      mode: WheelMode.tools,
      supportedCategories: [FileCategory.image],
      accentColor: AppColors.accentGreen,
      badge: 'SAFE',
    ),
    PetalItem(
      id: 'tool:ocr',
      label: 'OCR Text',
      sublabel: 'ML Kit Scan',
      icon: Icons.document_scanner_rounded,
      mode: WheelMode.tools,
      supportedCategories: [FileCategory.image, FileCategory.pdf],
      accentColor: AppColors.dropdialOrange,
      badge: 'ON-DEVICE',
    ),
    PetalItem(
      id: 'tool:watermark',
      label: 'Watermark',
      sublabel: 'Badge or Logo',
      icon: Icons.branding_watermark_rounded,
      mode: WheelMode.tools,
      supportedCategories: [FileCategory.image, FileCategory.pdf],
      accentColor: AppColors.accentAmber,
    ),
    PetalItem(
      id: 'tool:multi_to_pdf',
      label: 'Make PDF',
      sublabel: 'Combine Photos',
      icon: Icons.note_add_rounded,
      mode: WheelMode.tools,
      supportedCategories: [FileCategory.image],
      accentColor: AppColors.accentRed,
      badge: 'MULTI',
    ),
    PetalItem(
      id: 'tool:make_icon',
      label: 'Make Icon',
      sublabel: 'Favicon & App',
      icon: Icons.touch_app_rounded,
      mode: WheelMode.tools,
      supportedCategories: [FileCategory.image],
      accentColor: AppColors.accentBlue,
    ),
    PetalItem(
      id: 'tool:filter',
      label: 'Adjust',
      sublabel: 'B&W / Sepia / EV',
      icon: Icons.tune_rounded,
      mode: WheelMode.tools,
      supportedCategories: [FileCategory.image],
      accentColor: AppColors.accentPurple,
    ),
    PetalItem(
      id: 'tool:pdf_merge',
      label: 'Merge PDF',
      sublabel: 'Join Documents',
      icon: Icons.call_merge_rounded,
      mode: WheelMode.tools,
      supportedCategories: [FileCategory.pdf],
      accentColor: AppColors.accentRed,
    ),
  ];

  /// Universal file actions petals (matching macOS Catalog.fileActions)
  static const List<PetalItem> allActions = [
    PetalItem(
      id: 'action:share',
      label: 'Share',
      sublabel: 'System Sheet',
      icon: Icons.ios_share_rounded,
      mode: WheelMode.actions,
      accentColor: AppColors.dropdialOrange,
      badge: 'QUICK',
    ),
    PetalItem(
      id: 'action:save_downloads',
      label: 'Save File',
      sublabel: 'To Downloads',
      icon: Icons.file_download_rounded,
      mode: WheelMode.actions,
      accentColor: AppColors.accentGreen,
    ),
    PetalItem(
      id: 'action:copy_file',
      label: 'Copy File',
      sublabel: 'To Clipboard',
      icon: Icons.content_copy_rounded,
      mode: WheelMode.actions,
      accentColor: AppColors.primaryCyan,
    ),
    PetalItem(
      id: 'action:copy_path',
      label: 'Copy Path',
      sublabel: 'Full File URI',
      icon: Icons.link_rounded,
      mode: WheelMode.actions,
      accentColor: AppColors.textSecondary,
    ),
    PetalItem(
      id: 'action:info',
      label: 'Details',
      sublabel: 'Metadata & EXIF',
      icon: Icons.info_rounded,
      mode: WheelMode.actions,
      accentColor: AppColors.accentAmber,
    ),
    PetalItem(
      id: 'action:preview',
      label: 'Quick Look',
      sublabel: 'Full Preview',
      icon: Icons.visibility_rounded,
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
