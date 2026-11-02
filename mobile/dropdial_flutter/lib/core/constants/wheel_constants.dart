import 'dart:math' as math;

/// Core geometry, physics, and layout constants for DropDial Mobile
class WheelConstants {
  // Geometry
  static const double hubRadius = 60.0;
  static const double innerRadius = 74.0;
  static const double outerRadius = 185.0;
  static const double keycapCornerRadius = 14.0;
  static const double keycapGapAngle = 0.035; // radians (~2 degrees gap between petals)
  
  // Angle definitions (in radians)
  // 12 o'clock is -pi/2 (-90 deg). Visible semicircle spans from -pi to 0.
  static const double triggerApexAngle = -math.pi / 2; // -90 degrees (apex trigger)
  static const double visibleArcStart = -math.pi;       // 180 deg (left edge)
  static const double visibleArcEnd = 0.0;             // 0 deg (right edge)
  static const double visibleArcSpan = math.pi;        // 180 degrees
  
  // Angular spacing
  static const double petalSectorAngle = math.pi / 6; // 30 degrees per petal (6 petals in 180 deg)
  
  // Physics & Inertia
  static const double frictionDecay = 0.88; // Per-frame velocity damping
  static const double minVelocityStop = 0.001; // rad/frame stop threshold
  static const double maxFlingVelocity = 0.45; // Max rotational flick speed
  static const double springTension = 120.0;
  
  // Detents & Snapping
  static const double magneticSnapDistance = petalSectorAngle * 0.4;
  
  // Animation Durations
  static const Duration bloomDuration = Duration(milliseconds: 400);
  static const Duration snapDuration = Duration(milliseconds: 280);
  static const Duration modeSwitchDuration = Duration(milliseconds: 320);
}
