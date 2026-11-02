import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../domain/models/file_token.dart';

class FileDetailsCard extends StatelessWidget {
  final FileToken? file;
  final VoidCallback onClear;
  final VoidCallback onPickNew;

  const FileDetailsCard({
    super.key,
    required this.file,
    required this.onClear,
    required this.onPickNew,
  });

  @override
  Widget build(BuildContext context) {
    if (file == null) {
      return GestureDetector(
        onTap: onPickNew,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.surface.withOpacity(0.8),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.border,
              style: BorderStyle.solid,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryCyan.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.file_upload_outlined,
                  color: AppColors.primaryCyan,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ready for File Intake',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Share sheet, Vol Up+Down, or tap to browse',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textMuted,
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderBright),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // File Icon Badge
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primaryCyan.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.insert_drive_file_rounded,
              color: AppColors.primaryCyan,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),

          // File Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  file!.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      file!.formattedSize,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('•', style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.accentGreen.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.lock_outline_rounded, color: AppColors.accentGreen, size: 10),
                          SizedBox(width: 3),
                          Text(
                            '100% OFFLINE',
                            style: TextStyle(
                              color: AppColors.accentGreen,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Action buttons: swap & remove
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textMuted),
            onPressed: onClear,
            tooltip: 'Remove file',
          ),
        ],
      ),
    );
  }
}
