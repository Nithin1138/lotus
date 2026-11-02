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
    const innerCorner = 8.0;
    final outerInset = outerCorner / outerR;
    final innerInset = innerCorner / innerR;

    // Draw background track arc
    final trackPaint = Paint()
      ..color = AppColors.surfaceVariant.withOpacity(0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (outerR - innerR);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: midR),
      -math.pi,
      math.pi,
      false,
      trackPaint,
    );

    // Render each petal
    for (int i = 0; i < count; i++) {
      // Base angle: 12 o'clock (-pi/2) + index * sectorAngle + rotation
      double angle = -math.pi / 2 + (i * sectorAngle) + rotation;

      // Wrap angle to be within [-2pi, 2pi]
      while (angle < -math.pi - sectorAngle) {
        angle += count * sectorAngle;
      }
      while (angle > sectorAngle) {
        angle -= count * sectorAngle;
      }

      // Check visibility: visible arc is roughly [-pi - 0.3, 0.3]
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

      // 1. Draw 3D Sidewall Shadow underneath
      final sidePath = path.shift(const Offset(0, 4));
      final sidePaint = Paint()
        ..color = isFocused
            ? (petal.accentColor?.withOpacity(0.5) ?? AppColors.petalActiveSide)
            : AppColors.petalNormalSide
        ..style = PaintingStyle.fill;
      canvas.drawPath(sidePath, sidePaint);

      // 2. Draw Keycap Face
      final facePaint = Paint()..style = PaintingStyle.fill;
      if (isFocused) {
        facePaint.shader = LinearGradient(
          colors: [
            petal.accentColor ?? AppColors.primaryCyan,
            (petal.accentColor ?? AppColors.primaryCyan).withOpacity(0.85),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ).createShader(path.getBounds());
      } else {
        facePaint.color = AppColors.petalNormalFace;
      }
      canvas.drawPath(path, facePaint);

      // 3. Draw Keycap Border
      final borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = isFocused ? 2.0 : 1.0
        ..color = isFocused
            ? (petal.accentColor ?? AppColors.petalActiveBorder)
            : AppColors.petalNormalBorder;
      canvas.drawPath(path, borderPaint);

      // 4. Draw Focus Glow if active
      if (isFocused) {
        final glowPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.0
          ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 8)
          ..color = (petal.accentColor ?? AppColors.primaryCyan).withOpacity(0.6);
        canvas.drawPath(path, glowPaint);
      }

      // 5. Draw Petal Content (Icon + Label + Sublabel)
      _drawPetalContent(
        canvas: canvas,
        center: center,
        angle: angle,
        midRadius: midR,
        petal: petal,
        isFocused: isFocused,
      );
    }

    // 6. Draw 12 o'clock Apex Indicator
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

    // Start at inner arc + corner
    final p0 = polar(innerR + innerCorner, start);
    path.moveTo(p0.dx, p0.dy);

    // Line to outer radius - corner
    final p1 = polar(outerR - outerCorner, start);
    path.lineTo(p1.dx, p1.dy);

    // Corner quadratic bezier to outer arc
    final pCorner1 = polar(outerR, start);
    final pOuterStart = polar(outerR, start + outerInset);
    path.quadraticBezierTo(pCorner1.dx, pCorner1.dy, pOuterStart.dx, pOuterStart.dy);

    // Outer circular arc
    final outerRect = Rect.fromCircle(center: center, radius: outerR);
    final sweepAngle = (end - outerInset) - (start + outerInset);
    path.arcTo(outerRect, start + outerInset, sweepAngle, false);

    // Corner quadratic bezier to descending side
    final pCorner2 = polar(outerR, end);
    final p2 = polar(outerR - outerCorner, end);
    path.quadraticBezierTo(pCorner2.dx, pCorner2.dy, p2.dx, p2.dy);

    // Line down to inner radius + corner
    final p3 = polar(innerR + innerCorner, end);
    path.lineTo(p3.dx, p3.dy);

    // Corner quadratic bezier to inner arc
    final pCorner3 = polar(innerR, end);
    final pInnerEnd = polar(innerR, end - innerInset);
    path.quadraticBezierTo(pCorner3.dx, pCorner3.dy, pInnerEnd.dx, pInnerEnd.dy);

    // Inner circular arc (in reverse sweep)
    final innerRect = Rect.fromCircle(center: center, radius: innerR);
    final innerSweep = (start + innerInset) - (end - innerInset);
    path.arcTo(innerRect, end - innerInset, innerSweep, false);

    // Corner quadratic bezier back to start
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

    // Translate to petal center point
    final px = center.dx + midRadius * math.cos(angle);
    final py = center.dy + midRadius * math.sin(angle);
    canvas.translate(px, py);

    // Rotate so text is upright (tangential to the circle)
    canvas.rotate(angle + math.pi / 2);

    final textColor = isFocused ? AppColors.petalActiveText : AppColors.textPrimary;
    final subtextColor = isFocused
        ? AppColors.petalActiveText.withOpacity(0.8)
        : AppColors.textSecondary;

    // Draw Icon
    final iconSpan = TextSpan(
      text: String.fromCharCode(petal.icon.codePoint),
      style: TextStyle(
        fontSize: 22,
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

    // Draw Main Label
    final labelSpan = TextSpan(
      text: petal.label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
        color: textColor,
      ),
    );
    final labelPainter = TextPainter(
      text: labelSpan,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    labelPainter.paint(canvas, Offset(-labelPainter.width / 2, -2));

    // Draw Sublabel
    final sublabelSpan = TextSpan(
      text: petal.sublabel,
      style: TextStyle(
        fontSize: 9.5,
        fontWeight: FontWeight.w500,
        color: subtextColor,
      ),
    );
    final sublabelPainter = TextPainter(
      text: sublabelSpan,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    sublabelPainter.paint(canvas, Offset(-sublabelPainter.width / 2, 14));

    // Optional Badge (e.g. "AI ML", "POPULAR", "LOSSLESS")
    if (petal.badge != null && !isFocused) {
      final badgeSpan = TextSpan(
        text: petal.badge!,
        style: const TextStyle(
          fontSize: 7.5,
          fontWeight: FontWeight.bold,
          color: AppColors.primaryCyan,
        ),
      );
      final badgePainter = TextPainter(
        text: badgeSpan,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout();
      badgePainter.paint(canvas, Offset(-badgePainter.width / 2, 27));
    }

    canvas.restore();
  }

  void _drawApexNeedle(Canvas canvas, Offset center, double outerR) {
    // 12 o'clock needle indicator at the top apex
    final needleTop = Offset(center.dx, center.dy - outerR - 10);
    final needlePath = Path()
      ..moveTo(needleTop.dx - 6, needleTop.dy - 6)
      ..lineTo(needleTop.dx + 6, needleTop.dy - 6)
      ..lineTo(needleTop.dx, needleTop.dy)
      ..close();

    final needlePaint = Paint()
      ..color = AppColors.primaryCyan
      ..style = PaintingStyle.fill;
    canvas.drawPath(needlePath, needlePaint);

    final needleGlow = Paint()
      ..color = AppColors.primaryCyan.withOpacity(0.5)
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
