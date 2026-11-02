import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/wheel_constants.dart';
import '../../domain/models/petal_item.dart';

class SemiCircleWheelPainter extends CustomPainter {
  final List<PetalItem> petals;
  final double rotation;
  final int focusedIndex;
  final double bloomScale;

  SemiCircleWheelPainter({
    required this.petals,
    required this.rotation,
    required this.focusedIndex,
    this.bloomScale = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (petals.isEmpty) return;

    final center = Offset(size.width / 2, size.height);
    final count = petals.length;
    final sectorAngle = WheelConstants.petalSectorAngle;
    final half = sectorAngle / 2;
    const gap = WheelConstants.keycapGapAngle;

    final innerR = WheelConstants.innerRadius * bloomScale;
    final outerR = WheelConstants.outerRadius * bloomScale;
    final midR = (innerR + outerR) / 2;

    const outerCorner = 14.0;
    const innerCorner = 7.0;
    final outerInset = outerCorner / outerR;
    final innerInset = innerCorner / innerR;

    // 1. Soft Outer Halo / Backing Disc (matches macOS DropWheelWindow halo)
    final haloRect = Rect.fromCircle(center: center, radius: outerR + 10);
    final haloPaint = Paint()
      ..color = AppColors.haloBackdrop.withValues(alpha: 0.85)
      ..style = PaintingStyle.fill;
    canvas.drawArc(haloRect, -math.pi, math.pi, true, haloPaint);

    final trackPaint = Paint()
      ..color = AppColors.surfaceVariant.withValues(alpha: 0.40)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (outerR - innerR);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: midR),
      -math.pi,
      math.pi,
      false,
      trackPaint,
    );

    // 2. Render each petal with cushion geometry
    for (int i = 0; i < count; i++) {
      double angle = -math.pi / 2 + (i * sectorAngle) + rotation;

      while (angle < -math.pi - sectorAngle) {
        angle += count * sectorAngle;
      }
      while (angle > sectorAngle) {
        angle -= count * sectorAngle;
      }

      // Visible arc roughly [-pi - 0.4, 0.4]
      if (angle < -math.pi - 0.4 || angle > 0.4) {
        continue;
      }

      final petal = petals[i];
      final isFocused = (i == focusedIndex);

      final start = angle - half + gap;
      final end = angle + half - gap;

      final path = _buildKeycapPath(
        center: center,
        innerR: innerR,
        outerR: outerR,
        start: start,
        end: end,
        outerCorner: outerCorner,
        innerCorner: innerCorner,
        outerInset: outerInset,
        innerInset: innerInset,
      );

      // 3D Raised Sidewall (matches DropDial desktop keycap sidewall)
      final sidePath = path.shift(const Offset(0, 3.5));
      final sidePaint = Paint()
        ..color = isFocused
            ? (petal.accentColor?.withValues(alpha: 0.6) ?? AppColors.petalActiveSide)
            : AppColors.petalNormalSide
        ..style = PaintingStyle.fill;
      canvas.drawPath(sidePath, sidePaint);

      // Petal Face Fill
      final facePaint = Paint()..style = PaintingStyle.fill;
      if (isFocused) {
        final activeColor = petal.accentColor ?? AppColors.dropdialOrange;
        facePaint.shader = LinearGradient(
          colors: [
            activeColor,
            Color.lerp(activeColor, Colors.black, 0.15) ?? activeColor,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(path.getBounds());
      } else {
        facePaint.color = AppColors.petalNormalFace;
      }
      canvas.drawPath(path, facePaint);

      // Crisp 1px Outline Stroke (macOS style)
      final borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isFocused ? 1.8 : 1.0
        ..color = isFocused
            ? (petal.accentColor ?? AppColors.petalActiveBorder)
            : AppColors.petalNormalBorder;
      canvas.drawPath(path, borderPaint);

      // Focus Glow Filter
      if (isFocused) {
        final activeColor = petal.accentColor ?? AppColors.dropdialOrange;
        final glowPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0
          ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 8)
          ..color = activeColor.withValues(alpha: 0.45);
        canvas.drawPath(path, glowPaint);
      }

      // Petal Content (Icon + Label + Sublabel)
      _drawPetalContent(
        canvas: canvas,
        center: center,
        angle: angle,
        midRadius: midR,
        petal: petal,
        isFocused: isFocused,
      );
    }

    // 3. Side & Page Indicator Dots (matching macOS DropWheelWindow:1020-1050)
    _drawPaginationDots(canvas, center, outerR);

    // 4. 12 o'clock Apex Indicator Needle
    _drawApexNeedle(canvas, center, outerR);
  }

  Path _buildKeycapPath({
    required Offset center,
    required double innerR,
    required double outerR,
    required double start,
    required double end,
    required double outerCorner,
    required double innerCorner,
    required double outerInset,
    required double innerInset,
  }) {
    Offset polar(double r, double a) =>
        Offset(center.dx + r * math.cos(a), center.dy + r * math.sin(a));

    final path = Path();

    final p0 = polar(innerR + innerCorner, start);
    path.moveTo(p0.dx, p0.dy);

    final p1 = polar(outerR - outerCorner, start);
    path.lineTo(p1.dx, p1.dy);

    final pCorner1 = polar(outerR, start);
    final pOuterStart = polar(outerR, start + outerInset);
    path.quadraticBezierTo(pCorner1.dx, pCorner1.dy, pOuterStart.dx, pOuterStart.dy);

    final outerRect = Rect.fromCircle(center: center, radius: outerR);
    final sweepAngle = (end - outerInset) - (start + outerInset);
    path.arcTo(outerRect, start + outerInset, sweepAngle, false);

    final pCorner2 = polar(outerR, end);
    final p2 = polar(outerR - outerCorner, end);
    path.quadraticBezierTo(pCorner2.dx, pCorner2.dy, p2.dx, p2.dy);

    final p3 = polar(innerR + innerCorner, end);
    path.lineTo(p3.dx, p3.dy);

    final pCorner3 = polar(innerR, end);
    final pInnerEnd = polar(innerR, end - innerInset);
    path.quadraticBezierTo(pCorner3.dx, pCorner3.dy, pInnerEnd.dx, pInnerEnd.dy);

    final innerRect = Rect.fromCircle(center: center, radius: innerR);
    final innerSweep = (start + innerInset) - (end - innerInset);
    path.arcTo(innerRect, end - innerInset, innerSweep, false);

    final pCorner4 = polar(innerR, start);
    path.quadraticBezierTo(pCorner4.dx, pCorner4.dy, p0.dx, p0.dy);

    path.close();
    return path;
  }

  void _drawPetalContent({
    required Canvas canvas,
    required Offset center,
    required double angle,
    required double midRadius,
    required PetalItem petal,
    required bool isFocused,
  }) {
    canvas.save();

    final px = center.dx + midRadius * math.cos(angle);
    final py = center.dy + midRadius * math.sin(angle);
    canvas.translate(px, py);
    canvas.rotate(angle + math.pi / 2);

    final textColor = isFocused ? AppColors.petalActiveText : AppColors.textPrimary;
    final subtextColor = isFocused
        ? AppColors.petalActiveText.withValues(alpha: 0.85)
        : AppColors.textSecondary;

    // 1. Draw Icon
    final iconSpan = TextSpan(
      text: String.fromCharCode(petal.icon.codePoint),
      style: TextStyle(
        fontSize: 21,
        fontFamily: petal.icon.fontFamily,
        package: petal.icon.fontPackage,
        color: textColor,
      ),
    );
    final iconPainter = TextPainter(
      text: iconSpan,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    iconPainter.paint(canvas, Offset(-iconPainter.width / 2, -30));

    // 2. Draw Main Title
    final labelSpan = TextSpan(
      text: petal.label,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: isFocused ? FontWeight.w800 : FontWeight.w700,
        letterSpacing: 0.3,
        color: textColor,
      ),
    );
    final labelPainter = TextPainter(
      text: labelSpan,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    labelPainter.paint(canvas, Offset(-labelPainter.width / 2, -4));

    // 3. Draw Sublabel
    final sublabelSpan = TextSpan(
      text: petal.sublabel,
      style: TextStyle(
        fontSize: 9.0,
        fontWeight: FontWeight.w500,
        color: subtextColor,
      ),
    );
    final sublabelPainter = TextPainter(
      text: sublabelSpan,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    sublabelPainter.paint(canvas, Offset(-sublabelPainter.width / 2, 12));

    // 4. Optional Chip Badge (e.g. "AUTO", "LOSSLESS")
    if (petal.badge != null && !isFocused) {
      final badgeSpan = TextSpan(
        text: petal.badge!,
        style: TextStyle(
          fontSize: 7.5,
          fontWeight: FontWeight.bold,
          color: petal.accentColor ?? AppColors.dropdialOrange,
        ),
      );
      final badgePainter = TextPainter(
        text: badgeSpan,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout();
      badgePainter.paint(canvas, Offset(-badgePainter.width / 2, 24));
    }

    canvas.restore();
  }

  void _drawPaginationDots(Canvas canvas, Offset center, double outerR) {
    if (petals.length <= 6) return;

    final totalSides = (petals.length + 5) ~/ 6;
    final currentSide = (focusedIndex ~/ 6).clamp(0, totalSides - 1);
    const double dotSpacing = 10.0;
    final double totalW = (totalSides - 1) * dotSpacing;
    final double startX = center.dx - (totalW / 2);
    final double dotY = center.dy - outerR - 22;

    for (int i = 0; i < totalSides; i++) {
      final isCurrent = (i == currentSide);
      final dx = startX + (i * dotSpacing);
      final dotPaint = Paint()
        ..color = isCurrent
            ? AppColors.dropdialOrange
            : Colors.white.withValues(alpha: 0.3)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(dx, dotY), isCurrent ? 3.5 : 2.2, dotPaint);
    }
  }

  void _drawApexNeedle(Canvas canvas, Offset center, double outerR) {
    final needleTop = Offset(center.dx, center.dy - outerR - 6);
    final needlePath = Path()
      ..moveTo(needleTop.dx - 5, needleTop.dy - 6)
      ..lineTo(needleTop.dx + 5, needleTop.dy - 6)
      ..lineTo(needleTop.dx, needleTop.dy)
      ..close();

    final needlePaint = Paint()
      ..color = AppColors.dropdialOrange
      ..style = PaintingStyle.fill;
    canvas.drawPath(needlePath, needlePaint);

    final needleGlow = Paint()
      ..color = AppColors.dropdialOrange.withValues(alpha: 0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawPath(needlePath, needleGlow);
  }

  @override
  bool shouldRepaint(covariant SemiCircleWheelPainter oldDelegate) {
    return oldDelegate.rotation != rotation ||
        oldDelegate.focusedIndex != focusedIndex ||
        oldDelegate.petals != petals ||
        oldDelegate.bloomScale != bloomScale;
  }
}
