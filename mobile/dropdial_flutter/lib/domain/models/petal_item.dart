import 'package:flutter/material.dart';
import 'file_token.dart';
import 'wheel_mode.dart';

class PetalItem {
  final String id;
  final String label;
  final String sublabel;
  final IconData icon;
  final WheelMode mode;
  final List<FileCategory> supportedCategories;
  final Color? accentColor;
  final String? badge;
  final Map<String, dynamic> defaultParams;

  const PetalItem({
    required this.id,
    required this.label,
    required this.sublabel,
    required this.icon,
    required this.mode,
    this.supportedCategories = const [],
    this.accentColor,
    this.badge,
    this.defaultParams = const {},
  });

  bool supportsCategory(FileCategory category) {
    if (supportedCategories.isEmpty) return true; // Universal
    return supportedCategories.contains(category);
  }
}

