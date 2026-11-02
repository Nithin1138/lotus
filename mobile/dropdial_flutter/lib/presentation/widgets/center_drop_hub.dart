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
                width: 2.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: file != null
                      ? AppColors.dropdialOrange.withValues(alpha: 0.35)
                      : Colors.black.withValues(alpha: 0.65),
                  blurRadius: 18,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 1. Thumbnail Preview Image or Official DropDial Logo
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
                  _buildEmptyStateWithLogo(r),

                // 2. Subtle Dark Radial Vignette on Thumbnail
                if (file != null)
                  Container(
                    width: r * 2,
                    height: r * 2,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.70),
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
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: AppColors.background.withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: AppColors.dropdialOrange.withValues(alpha: 0.6),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        file.isBatch ? '${file.count} FILES' : file.extension.toUpperCase(),
                        style: const TextStyle(
                          color: AppColors.dropdialOrange,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
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
                      strokeWidth: 3.5,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.dropdialOrange),
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

  Widget _buildEmptyStateWithLogo(double r) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Official DropDial Logo
        Image.asset(
          'assets/icons/app_logo.png',
          width: 44,
          height: 44,
          errorBuilder: (context, error, stackTrace) => const Icon(
            Icons.add_circle_outline_rounded,
            color: AppColors.dropdialOrange,
            size: 36,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'DROP FILE',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
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
        icon = Icons.movie_creation_rounded;
        color = AppColors.dropdialOrange;
        break;
      case FileCategory.audio:
        icon = Icons.graphic_eq_rounded;
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

    return Icon(icon, size: 38, color: color);
  }
}
