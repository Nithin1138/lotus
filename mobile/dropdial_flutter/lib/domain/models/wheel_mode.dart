enum WheelMode {
  formats,
  tools,
  actions,
}

extension WheelModeExtension on WheelMode {
  String get label {
    switch (this) {
      case WheelMode.formats:
        return 'Convert';
      case WheelMode.tools:
        return 'Tools';
      case WheelMode.actions:
        return 'Actions';
    }
  }

  String get shortcutSymbol {
    switch (this) {
      case WheelMode.formats:
        return '⇧';
      case WheelMode.tools:
        return '⌘';
      case WheelMode.actions:
        return '⌃';
    }
  }

  String get description {
    switch (this) {
      case WheelMode.formats:
        return 'Convert to target format';
      case WheelMode.tools:
        return 'Modify, compress & process';
      case WheelMode.actions:
        return 'System & file operations';
    }
  }
}
