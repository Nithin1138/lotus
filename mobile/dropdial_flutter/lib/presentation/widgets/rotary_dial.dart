import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../core/constants/wheel_constants.dart';
import '../../domain/models/petal_item.dart';
import '../controllers/dial_controller.dart';
import 'semi_circle_wheel_painter.dart';

class RotaryDial extends StatefulWidget {
  final DialController controller;
  final ValueChanged<PetalItem>? onPetalTap;
  final double bloomScale;

  const RotaryDial({
    super.key,
    required this.controller,
    this.onPetalTap,
    this.bloomScale = 1.0,
  });

  @override
  State<RotaryDial> createState() => _RotaryDialState();
}

class _RotaryDialState extends State<RotaryDial> with SingleTickerProviderStateMixin {
  double? _lastTouchAngle;
  double _angularVelocity = 0.0;
  DateTime _lastTouchTime = DateTime.now();

  late AnimationController _inertiaController;
  Animation<double>? _snapAnimation;

  @override
  void initState() {
    super.initState();
    _inertiaController = AnimationController(
      vsync: this,
      duration: WheelConstants.snapDuration,
    )..addListener(_onInertiaStep);
  }

  @override
  void dispose() {
    _inertiaController.dispose();
    super.dispose();
  }

  void _onInertiaStep() {
    if (_snapAnimation != null) {
      widget.controller.setRotation(_snapAnimation!.value);
    }
  }

  void _onPanStart(DragStartDetails details, Size size) {
    _inertiaController.stop();
    _snapAnimation = null;
    final center = Offset(size.width / 2, size.height);
    final pos = details.localPosition;
    _lastTouchAngle = math.atan2(pos.dy - center.dy, pos.dx - center.dx);
    _lastTouchTime = DateTime.now();
    _angularVelocity = 0.0;
  }

  void _onPanUpdate(DragUpdateDetails details, Size size) {
    final center = Offset(size.width / 2, size.height);
    final pos = details.localPosition;
    final currentAngle = math.atan2(pos.dy - center.dy, pos.dx - center.dx);
    final now = DateTime.now();

    if (_lastTouchAngle != null) {
      double delta = currentAngle - _lastTouchAngle!;

      // Handle -pi to pi crossing
      if (delta > math.pi) delta -= 2 * math.pi;
      if (delta < -math.pi) delta += 2 * math.pi;

      final dt = now.difference(_lastTouchTime).inMicroseconds / 1000000.0;
      if (dt > 0.001) {
        _angularVelocity = (_angularVelocity * 0.4) + ((delta / dt) * 0.6);
      }

      widget.controller.updateRotation(delta);
    }

    _lastTouchAngle = currentAngle;
    _lastTouchTime = now;
  }

  void _onPanEnd(DragEndDetails details, Size size) {
    _lastTouchAngle = null;

    // Apply snap to nearest petal
    final currentRot = widget.controller.rotation;
    final sectorAngle = WheelConstants.petalSectorAngle;
    
    // Add momentum projection
    final momentumOffset = (_angularVelocity * 0.06).clamp(
      -sectorAngle * 2,
      sectorAngle * 2,
    );
    final projectedRot = currentRot + momentumOffset;
    final targetSector = (projectedRot / sectorAngle).round();
    final targetRot = targetSector * sectorAngle;

    _snapAnimation = Tween<double>(
      begin: currentRot,
      end: targetRot,
    ).animate(CurvedAnimation(
      parent: _inertiaController,
      curve: Curves.easeOutBack,
    ));

    _inertiaController.forward(from: 0.0).then((_) {
      widget.controller.snapToNearest();
    });
  }

  void _onTapUp(TapUpDetails details, Size size) {
    final center = Offset(size.width / 2, size.height);
    final pos = details.localPosition;
    final dx = pos.dx - center.dx;
    final dy = pos.dy - center.dy;
    final dist = math.sqrt(dx * dx + dy * dy);

    // Only process taps within petal arc zone
    if (dist < WheelConstants.innerRadius || dist > WheelConstants.outerRadius + 20) {
      return;
    }

    final tapAngle = math.atan2(dy, dx);
    final petals = widget.controller.petals;
    final sectorAngle = WheelConstants.petalSectorAngle;
    final count = petals.length;

    for (int i = 0; i < count; i++) {
      double angle = -math.pi / 2 + (i * sectorAngle) + widget.controller.rotation;
      while (angle < -math.pi - sectorAngle) {
        angle += count * sectorAngle;
      }
      while (angle > sectorAngle) {
        angle -= count * sectorAngle;
      }

      final diff = (tapAngle - angle).abs();
      if (diff < sectorAngle / 2) {
        // Tapped petal i!
        final petal = petals[i];
        widget.onPetalTap?.call(petal);
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (d) => _onPanStart(d, size),
              onPanUpdate: (d) => _onPanUpdate(d, size),
              onPanEnd: (d) => _onPanEnd(d, size),
              onTapUp: (d) => _onTapUp(d, size),
              child: CustomPaint(
                size: size,
                painter: SemiCircleWheelPainter(
                  petals: widget.controller.petals,
                  rotation: widget.controller.rotation,
                  focusedIndex: widget.controller.focusedPetalIndex,
                  bloomScale: widget.bloomScale,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
