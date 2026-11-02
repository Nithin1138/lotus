import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../domain/models/wheel_mode.dart';

class ModeSelectorBar extends StatelessWidget {
  final WheelMode activeMode;
  final ValueChanged<WheelMode> onModeChanged;

  const ModeSelectorBar({
    super.key,
    required this.activeMode,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: WheelMode.values.map((mode) {
          final isSelected = (mode == activeMode);
          return Expanded(
            child: GestureDetector(
              onTap: () => onModeChanged(mode),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeInOut,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.petalActiveFace : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: AppColors.primaryCyan.withOpacity(0.35),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ]
                      : [],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      _getIcon(mode),
                      size: 16,
                      color: isSelected ? AppColors.petalActiveText : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      mode.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                        color: isSelected ? AppColors.petalActiveText : AppColors.textSecondary,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  IconData _getIcon(WheelMode mode) {
    switch (mode) {
      case WheelMode.formats:
        return Icons.swap_horiz_rounded;
      case WheelMode.tools:
        return Icons.build_outlined;
      case WheelMode.actions:
        return Icons.bolt_rounded;
    }
  }
}
