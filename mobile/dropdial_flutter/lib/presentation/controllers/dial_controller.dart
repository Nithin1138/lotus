import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants/wheel_constants.dart';
import '../../core/services/haptic_service.dart';
import '../../domain/converters/conversion_catalog.dart';
import '../../domain/models/file_token.dart';
import '../../domain/models/petal_item.dart';
import '../../domain/models/wheel_mode.dart';
import '../../engine/conversion_orchestrator.dart';
import '../../engine/image_engine.dart';

class DialController extends ChangeNotifier {
  FileToken? _activeFile;
  WheelMode _activeMode = WheelMode.formats;
  List<PetalItem> _petals = [];

  // Rotation angle in radians
  double _rotation = 0.0;
  int _lastFocusedIndex = 0;

  bool _isExecuting = false;
  double _executionProgress = 0.0;
  ExecutionResult? _lastResult;

  final ImagePicker _imagePicker = ImagePicker();

  DialController() {
    _refreshPetals();
  }

  // Getters
  FileToken? get activeFile => _activeFile;
  WheelMode get activeMode => _activeMode;
  List<PetalItem> get petals => _petals;
  double get rotation => _rotation;
  bool get isExecuting => _isExecuting;
  double get executionProgress => _executionProgress;
  ExecutionResult? get lastResult => _lastResult;

  int get focusedPetalIndex {
    if (_petals.isEmpty) return 0;
    // 12 o'clock apex is -pi/2.
    // For each petal i with rest angle: -pi/2 + (i * sectorAngle) + rotation.
    // Petal i is at apex when its angle equals -pi/2 (i.e. i * sectorAngle + rotation ~= 0 mod 2pi).
    final anglePerPetal = WheelConstants.petalSectorAngle;
    final normalizedRot = -_rotation;
    final rawIndex = (normalizedRot / anglePerPetal).round();
    final clampedIndex = rawIndex % _petals.length;
    return clampedIndex < 0 ? clampedIndex + _petals.length : clampedIndex;
  }

  PetalItem? get focusedPetal {
    if (_petals.isEmpty) return null;
    final idx = focusedPetalIndex;
    if (idx >= 0 && idx < _petals.length) {
      return _petals[idx];
    }
    return null;
  }

  void setMode(WheelMode mode) {
    if (_activeMode == mode) return;
    _activeMode = mode;
    _rotation = 0.0;
    _refreshPetals();
    HapticService.snap();
    notifyListeners();
  }

  void updateRotation(double delta) {
    _rotation += delta;
    final newFocused = focusedPetalIndex;
    if (newFocused != _lastFocusedIndex) {
      _lastFocusedIndex = newFocused;
      HapticService.tick();
    }
    notifyListeners();
  }

  void snapToNearest() {
    if (_petals.isEmpty) return;
    final anglePerPetal = WheelConstants.petalSectorAngle;
    final targetSector = (_rotation / anglePerPetal).round();
    _rotation = targetSector * anglePerPetal;
    _lastFocusedIndex = focusedPetalIndex;
    HapticService.snap();
    notifyListeners();
  }

  void setRotation(double value) {
    _rotation = value;
    notifyListeners();
  }

  /// Ingest file from path
  Future<void> ingestFilePath(String path) async {
    final file = File(path);
    if (!file.existsSync()) return;

    final token = FileToken.fromFile(file);
    Uint8List? thumb;
    if (token.category == FileCategory.image) {
      thumb = await ImageEngine.generateThumbnail(file);
    }

    _activeFile = token.copyWith(thumbnailBytes: thumb);
    _refreshPetals();
    HapticService.trigger();
    notifyListeners();
  }

  /// Ingest multiple files
  Future<void> ingestFilePaths(List<String> paths) async {
    if (paths.isEmpty) return;
    if (paths.length == 1) {
      await ingestFilePath(paths.first);
      return;
    }

    final firstFile = File(paths.first);
    final token = FileToken.fromFile(firstFile);
    Uint8List? thumb;
    if (token.category == FileCategory.image) {
      thumb = await ImageEngine.generateThumbnail(firstFile);
    }

    _activeFile = token.copyWith(
      thumbnailBytes: thumb,
      batchPaths: paths,
    );
    _refreshPetals();
    HapticService.trigger();
    notifyListeners();
  }

  /// Open native file picker
  Future<void> pickFileFromStorage() async {
    final result = await FilePicker.pickFiles(
      type: FileType.any,
    );

    if (result.isNotEmpty) {
      final validPaths = result.map((f) => f.path).whereType<String>().toList();
      if (validPaths.isNotEmpty) {
        await ingestFilePaths(validPaths);
      }
    }
  }

  /// Pick photo from camera
  Future<void> pickFromCamera() async {
    final photo = await _imagePicker.pickImage(source: ImageSource.camera);
    if (photo != null) {
      await ingestFilePath(photo.path);
    }
  }

  /// Pick photo from gallery
  Future<void> pickFromGallery() async {
    final photo = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (photo != null) {
      await ingestFilePath(photo.path);
    }
  }

  /// Trigger execution on a specific petal
  Future<ExecutionResult> executePetal(PetalItem petal, {Map<String, dynamic>? params}) async {
    if (_activeFile == null) {
      final res = ExecutionResult(
        success: false,
        message: 'Please select a file first',
      );
      _lastResult = res;
      notifyListeners();
      return res;
    }

    _isExecuting = true;
    _executionProgress = 0.2;
    notifyListeners();
    HapticService.trigger();

    try {
      _executionProgress = 0.6;
      notifyListeners();

      final result = await ConversionOrchestrator.execute(
        petal: petal,
        fileToken: _activeFile!,
        customParams: params,
      );

      _executionProgress = 1.0;
      _isExecuting = false;
      _lastResult = result;

      if (result.success) {
        HapticService.success();
      }
      notifyListeners();
      return result;
    } catch (e) {
      _isExecuting = false;
      final result = ExecutionResult(
        success: false,
        message: 'Execution error: $e',
        error: e.toString(),
      );
      _lastResult = result;
      notifyListeners();
      return result;
    }
  }

  /// Trigger focused petal
  Future<ExecutionResult?> executeFocusedPetal() async {
    final petal = focusedPetal;
    if (petal != null) {
      return executePetal(petal);
    }
    return null;
  }

  void clearFile() {
    _activeFile = null;
    _lastResult = null;
    _refreshPetals();
    notifyListeners();
  }

  void _refreshPetals() {
    _petals = ConversionCatalog.getPetalsFor(
      mode: _activeMode,
      category: _activeFile?.category,
      currentExtension: _activeFile?.extension,
    );
    notifyListeners();
  }
}
