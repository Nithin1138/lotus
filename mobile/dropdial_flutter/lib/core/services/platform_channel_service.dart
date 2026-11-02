import 'dart:async';
import 'package:flutter/services.dart';

class PlatformChannelService {
  static const MethodChannel _intakeChannel = MethodChannel('com.dropdial.mobile/intake');
  static const MethodChannel _systemChannel = MethodChannel('com.dropdial.mobile/system');

  static final StreamController<List<String>> _sharedFilesController =
      StreamController<List<String>>.broadcast();

  static Stream<List<String>> get sharedFilesStream => _sharedFilesController.stream;

  static void initialize() {
    _intakeChannel.setMethodCallHandler((call) async {
      if (call.method == 'onFilesReceived') {
        final List<dynamic>? paths = call.arguments as List<dynamic>?;
        if (paths != null && paths.isNotEmpty) {
          final stringPaths = paths.map((e) => e.toString()).toList();
          _sharedFilesController.add(stringPaths);
        }
      }
    });
  }

  /// Retrieve files shared when the activity launched
  static Future<List<String>> getInitialSharedFiles() async {
    try {
      final List<dynamic>? files = await _intakeChannel.invokeMethod('getInitialSharedFiles');
      if (files != null) {
        return files.map((e) => e.toString()).toList();
      }
    } catch (_) {}
    return [];
  }

  /// Check if Volume Chord Accessibility Service is enabled
  static Future<bool> isAccessibilityServiceEnabled() async {
    try {
      final bool? enabled = await _systemChannel.invokeMethod('isAccessibilityEnabled');
      return enabled ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Open Accessibility Settings
  static Future<void> openAccessibilitySettings() async {
    try {
      await _systemChannel.invokeMethod('openAccessibilitySettings');
    } catch (_) {}
  }

  /// Check if SYSTEM_ALERT_WINDOW (display over other apps) permission is granted
  static Future<bool> canDrawOverlays() async {
    try {
      final bool? allowed = await _systemChannel.invokeMethod('canDrawOverlays');
      return allowed ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Open Overlay Permission Settings
  static Future<void> openOverlaySettings() async {
    try {
      await _systemChannel.invokeMethod('openOverlaySettings');
    } catch (_) {}
  }

  /// Toggle the background Floating Edge Dock overlay
  static Future<void> toggleFloatingOverlay(bool enabled) async {
    try {
      await _systemChannel.invokeMethod('toggleFloatingOverlay', {'enabled': enabled});
    } catch (_) {}
  }
}

