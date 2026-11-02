import 'package:flutter/services.dart';

class HapticService {
  static bool enabled = true;

  /// Crisp micro-tick when passing a petal boundary during rotation
  static Future<void> tick() async {
    if (!enabled) return;
    await HapticFeedback.selectionClick();
  }

  /// Magnetic lock snap when petal settles into 12 o'clock apex
  static Future<void> snap() async {
    if (!enabled) return;
    await HapticFeedback.mediumImpact();
  }

  /// Trigger action on petal tap or drop
  static Future<void> trigger() async {
    if (!enabled) return;
    await HapticFeedback.heavyImpact();
  }

  /// Operation completion vibration
  static Future<void> success() async {
    if (!enabled) return;
    await HapticFeedback.vibrate();
  }
}
