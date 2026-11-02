import 'package:flutter/material.dart';

class AppColors {
  // macOS DropDial Slate & Deep Obsidian
  static const Color background = Color(0xFF0F1115);
  static const Color surface = Color(0xFF171A20);
  static const Color surfaceVariant = Color(0xFF20242C);
  static const Color cardBg = Color(0xFF1C2027);
  static const Color haloBackdrop = Color(0xFF13161C);
  static const Color overlayDim = Color(0xB3000000);

  // Borders & Dividers (macOS 1px subtle borders)
  static const Color border = Color(0xFF2B323D);
  static const Color borderBright = Color(0xFF3E4756);
  static const Color borderSubtle = Color(0x1FFFFFFF); // 12% white stroke

  // Signature macOS DropDial Accents
  static const Color dropdialOrange = Color(0xFFFF6208); // macOS signature orange
  static const Color dropdialOrangeGlow = Color(0xFFFF4500);
  static const Color primaryCyan = Color(0xFF00E5FF);
  static const Color accentPurple = Color(0xFFB388FF);
  static const Color accentGreen = Color(0xFF00E676);
  static const Color accentAmber = Color(0xFFFFB300);
  static const Color accentRed = Color(0xFFFF5252);
  static const Color accentBlue = Color(0xFF2979FF);

  // Wheel Petal Palette (Matches macOS makeCushionPetal)
  static const Color petalNormalFace = Color(0xFF222730);
  static const Color petalNormalSide = Color(0xFF15181E);
  static const Color petalNormalBorder = Color(0x1FFFFFFF); // White with 0.12 alpha
  
  static const Color petalActiveFace = Color(0xFFFF6208); // macOS orange highlight
  static const Color petalActiveSide = Color(0xFFCC4400);
  static const Color petalActiveText = Color(0xFFFFFFFF);
  static const Color petalActiveBorder = Color(0xFFFF8533);

  // Hub Palette (Machined Digital Crown aesthetic)
  static const Color hubFace = Color(0xFF191D24);
  static const Color hubBorder = Color(0xFF343E4E);
  static const Color hubActiveBorder = Color(0xFFFF6208);

  // Typography
  static const Color textPrimary = Color(0xFFF8FAFC);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);
  static const Color textAccent = Color(0xFFFF6208);

  // Gradients
  static const LinearGradient orangeGradient = LinearGradient(
    colors: [Color(0xFFFF7A1A), Color(0xFFFF4D00)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient cyanGradient = LinearGradient(
    colors: [Color(0xFF00E5FF), Color(0xFF00B0FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient hubGradient = LinearGradient(
    colors: [Color(0xFF252B35), Color(0xFF13161C)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}
