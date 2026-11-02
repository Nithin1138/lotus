import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/wheel_constants.dart';
import '../../domain/models/file_token.dart';
import '../controllers/dial_controller.dart';

class CenterDropHub extends StatelessWidget {
  final DialController controller;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const CenterDropHub({
    super.key,
    required this.controller,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final file = controller.activeFile;
        final isExecuting = controller.isExecuting;
        final progress = controller.executionProgress;
        const double r = WheelConstants.hubRadius;

        return GestureDetector(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            width: r * 2,
            height: r * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.hubFace,
              border: Border.all(
                color: file != null ? AppColors.hubActiveBorder : AppColors.hubBorder,
                width: 2.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: file != null
                      ? AppColors.primaryCyan.withOpacity(0.25)
                      : Colors.black.withOpacity(0.6),
                  blurRadius: 18,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 1. Thumbnail Image or Empty State
                if (file != null && file.thumbnailBytes != null)
                  ClipOval(
                    child: Image.memory(
                      file.thumbnailBytes!,
                      width: r * 2,
                      height: r * 2,
                      fit: BoxFit.cover,
                    ),
                  )
                else if (file != null)
                  _buildFileCategoryIcon(file.category)
                else
                  _buildEmptyState(),

                // 2. Dim overlay on image for readability
                if (file != null)
                  Container(
                    width: r * 2,
                    height: r * 2,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.75),
                        ],
                        radius: 0.85,
                      ),
                    ),
                  ),

                // 3. File extension badge pill
                if (file != null && !isExecuting)
                  Positioned(
                    bottom: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.background.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.primaryCyan.withOpacity(0.5),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        file.isBatch ? '${file.count} FILES' : file.extension.toUpperCase(),
                        style: const TextStyle(
                          color: AppColors.primaryCyan,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),

                // 4. Progress Ring during execution
                if (isExecuting)
                  SizedBox(
                    width: r * 2 - 4,
                    height: r * 2 - 4,
                    child: CircularProgressIndicator(
                      value: progress > 0 ? progress : null,
                      strokeWidth: 4,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primaryCyan),
                      backgroundColor: AppColors.surfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.add_circle_outline_rounded,
          color: AppColors.primaryCyan.withOpacity(0.9),
          size: 32,
        ),
        const SizedBox(height: 4),
        const Text(
          'TAP FILE',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }

  Widget _buildFileCategoryIcon(FileCategory category) {
    IconData icon;
    Color color;

    switch (category) {
      case FileCategory.pdf:
        icon = Icons.picture_as_pdf_rounded;
        color = AppColors.accentRed;
        break;
      case FileCategory.document:
        icon = Icons.description_rounded;
        color = AppColors.accentBlue;
        break;
      case FileCategory.video:
        icon = Icons.videocam_rounded;
        color = AppColors.accentOrange;
        break;
      case FileCategory.audio:
        icon = Icons.audiotrack_rounded;
        color = AppColors.accentGreen;
        break;
      case FileCategory.archive:
        icon = Icons.folder_zip_rounded;
        color = AppColors.accentAmber;
        break;
      default:
        icon = Icons.insert_drive_file_rounded;
        color = AppColors.primaryCyan;
    }

    return Icon(icon, size: 42, color: color);
  }
}
