import 'package:flutter/material.dart';

class AppColors {
  // Deep Backgrounds
  static const Color background = Color(0xFF0D0F12);
  static const Color surface = Color(0xFF14181E);
  static const Color surfaceVariant = Color(0xFF1D232C);
  static const Color cardBg = Color(0xFF181E26);
  static const Color overlayDim = Color(0x99000000);

  // Borders & Dividers
  static const Color border = Color(0xFF26303D);
  static const Color borderBright = Color(0xFF384556);
  static const Color glowCyan = Color(0x4000E5FF);
  
  // Accents
  static const Color primaryCyan = Color(0xFF00E5FF);
  static const Color accentOrange = Color(0xFFFF6D00);
  static const Color accentPurple = Color(0xFFB388FF);
  static const Color accentGreen = Color(0xFF00E676);
  static const Color accentAmber = Color(0xFFFFAB00);
  static const Color accentRed = Color(0xFFFF5252);
  static const Color accentBlue = Color(0xFF2979FF);

  // Wheel Keycap Palettes
  static const Color petalNormalFace = Color(0xFF1E2530);
  static const Color petalNormalSide = Color(0xFF12161E);
  static const Color petalNormalBorder = Color(0xFF313D4E);
  
  static const Color petalActiveFace = Color(0xFF00E5FF);
  static const Color petalActiveSide = Color(0xFF00838F);
  static const Color petalActiveText = Color(0xFF051016);
  static const Color petalActiveBorder = Color(0xFF80F3FF);

  static const Color petalHoverFace = Color(0xFF2A3444);
  
  // Hub Colors
  static const Color hubFace = Color(0xFF161C24);
  static const Color hubBorder = Color(0xFF3B485A);
  static const Color hubActiveBorder = Color(0xFF00E5FF);

  // Text Colors
  static const Color textPrimary = Color(0xFFF1F5F9);
  static const Color textSecondary = Color(0xFF94A3B8);
  static const Color textMuted = Color(0xFF64748B);
  static const Color textCyan = Color(0xFF38BDF8);

  // Gradients
  static const LinearGradient cyanGradient = LinearGradient(
    colors: [Color(0xFF00E5FF), Color(0xFF00B0FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient hubGradient = LinearGradient(
    colors: [Color(0xFF212B36), Color(0xFF12171E)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const RadialGradient apexGlow = RadialGradient(
    colors: [Color(0x3300E5FF), Colors.transparent],
    radius: 0.8,
  );
}
