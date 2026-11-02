enum WheelMode {
  formats,
  tools,
  actions,
}

extension WheelModeExtension on WheelMode {
  String get label {
    switch (this) {
      case WheelMode.formats:
        return 'Formats';
      case WheelMode.tools:
        return 'Tools';
      case WheelMode.actions:
        return 'Actions';
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
