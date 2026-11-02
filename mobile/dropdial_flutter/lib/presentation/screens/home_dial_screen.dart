import 'dart:async';
import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/wheel_constants.dart';
import '../../core/services/platform_channel_service.dart';
import '../../domain/models/petal_item.dart';
import '../controllers/dial_controller.dart';
import '../widgets/action_result_sheet.dart';
import '../widgets/center_drop_hub.dart';
import '../widgets/file_details_card.dart';
import '../widgets/mode_selector_bar.dart';
import '../widgets/rotary_dial.dart';
import 'settings_shortcuts_screen.dart';

class HomeDialScreen extends StatefulWidget {
  const HomeDialScreen({super.key});

  @override
  State<HomeDialScreen> createState() => _HomeDialScreenState();
}

class _HomeDialScreenState extends State<HomeDialScreen> with SingleTickerProviderStateMixin {
  late final DialController _controller;
  late final AnimationController _bloomAnimationController;
  StreamSubscription<List<String>>? _sharedFilesSub;

  @override
  void initState() {
    super.initState();
    _controller = DialController();
    _bloomAnimationController = AnimationController(
      vsync: this,
      duration: WheelConstants.bloomDuration,
      value: 1.0,
    );

    _listenToSharedIntake();
  }

  void _listenToSharedIntake() {
    PlatformChannelService.getInitialSharedFiles().then((paths) {
      if (paths.isNotEmpty && mounted) {
        _controller.ingestFilePaths(paths).then((_) => _triggerBloom());
      }
    });

    _sharedFilesSub = PlatformChannelService.sharedFilesStream.listen((paths) {
      if (paths.isNotEmpty && mounted) {
        _controller.ingestFilePaths(paths).then((_) => _triggerBloom());
      }
    });
  }

  @override
  void dispose() {
    _sharedFilesSub?.cancel();
    _controller.dispose();
    _bloomAnimationController.dispose();
    super.dispose();
  }

  void _showMediaPickerModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.borderBright,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text(
                'Select File for DropDial',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.dropdialOrange.withValues(alpha: 0.15),
                  child: const Icon(Icons.folder_open_rounded, color: AppColors.dropdialOrange),
                ),
                title: const Text('Browse Files / Documents', style: TextStyle(color: AppColors.textPrimary)),
                subtitle: const Text('PDFs, images, videos, documents', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  _controller.pickFileFromStorage().then((_) => _triggerBloom());
                },
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.primaryCyan.withValues(alpha: 0.15),
                  child: const Icon(Icons.photo_library_rounded, color: AppColors.primaryCyan),
                ),
                title: const Text('Choose from Photo Gallery', style: TextStyle(color: AppColors.textPrimary)),
                subtitle: const Text('Camera roll, screenshots, albums', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  _controller.pickFromGallery().then((_) => _triggerBloom());
                },
              ),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.accentGreen.withValues(alpha: 0.15),
                  child: const Icon(Icons.camera_alt_rounded, color: AppColors.accentGreen),
                ),
                title: const Text('Take Photo / Document Scan', style: TextStyle(color: AppColors.textPrimary)),
                subtitle: const Text('Instant camera snapshot', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  _controller.pickFromCamera().then((_) => _triggerBloom());
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _triggerBloom() {
    _bloomAnimationController.forward(from: 0.0);
  }

  void _onPetalSelected(PetalItem petal) async {
    final result = await _controller.executePetal(petal);
    if (mounted) {
      ActionResultSheet.show(context, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // 1. macOS DropDial Header Bar with Official Logo
            _buildHeader(context),

            // 2. Mode Selector Bar (Convert | Tools | Actions)
            ListenableBuilder(
              listenable: _controller,
              builder: (context, _) => ModeSelectorBar(
                activeMode: _controller.activeMode,
                onModeChanged: (mode) {
                  _controller.setMode(mode);
                  _triggerBloom();
                },
              ),
            ),

            // 3. File Details Card
            ListenableBuilder(
              listenable: _controller,
              builder: (context, _) => FileDetailsCard(
                file: _controller.activeFile,
                onClear: () => _controller.clearFile(),
                onPickNew: _showMediaPickerModal,
              ),
            ),

            // 4. macOS-style Active Apex Trigger Pill
            _buildActiveApexTriggerBanner(),

            const Spacer(),

            // 5. Semi-Circular Rotary Wheel & Center Hub
            _buildSemiCircleWheelArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              // Official DropDial Logo Icon
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/icons/app_logo.png',
                  width: 32,
                  height: 32,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      gradient: AppColors.orangeGradient,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Text('D', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'DropDial',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    'THUMB-ARC RADIAL FAN',
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: AppColors.dropdialOrange,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.textSecondary, size: 22),
                tooltip: 'Select File',
                onPressed: _showMediaPickerModal,
              ),
              IconButton(
                icon: const Icon(Icons.tune_rounded, color: AppColors.textSecondary, size: 21),
                tooltip: 'Shortcuts & Hardware Chords',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsShortcutsScreen()),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActiveApexTriggerBanner() {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final focused = _controller.focusedPetal;
        if (focused == null) return const SizedBox.shrink();

        final activeColor = focused.accentColor ?? AppColors.dropdialOrange;

        return GestureDetector(
          onTap: () => _onPetalSelected(focused),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 36, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: activeColor.withValues(alpha: 0.65),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: activeColor.withValues(alpha: 0.22),
                  blurRadius: 10,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  focused.icon,
                  size: 15,
                  color: activeColor,
                ),
                const SizedBox(width: 7),
                Text(
                  'TRIGGER: ${focused.label.toUpperCase()}',
                  style: TextStyle(
                    color: activeColor,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(width: 5),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 11,
                  color: AppColors.textPrimary,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSemiCircleWheelArea() {
    const double wheelHeight = 220.0;

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.bottomCenter,
      children: [
        // 1. Thumb Arc Rotary Dial
        SizedBox(
          width: double.infinity,
          height: wheelHeight,
          child: AnimatedBuilder(
            animation: _bloomAnimationController,
            builder: (context, child) {
              return RotaryDial(
                controller: _controller,
                bloomScale: CurvedAnimation(
                  parent: _bloomAnimationController,
                  curve: Curves.easeOutBack,
                ).value,
                onPetalTap: (petal) => _onPetalSelected(petal),
              );
            },
          ),
        ),

        // 2. Rotary Sweep Guide Text (macOS style)
        Positioned(
          bottom: 74,
          child: IgnorePointer(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.arrow_back_ios_rounded, size: 9, color: AppColors.textMuted.withValues(alpha: 0.6)),
                const SizedBox(width: 4),
                Text(
                  'SWIPE TO ROTATE',
                  style: TextStyle(
                    color: AppColors.textMuted.withValues(alpha: 0.6),
                    fontSize: 8.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.arrow_forward_ios_rounded, size: 9, color: AppColors.textMuted.withValues(alpha: 0.6)),
              ],
            ),
          ),
        ),

        // 3. Center Drop Hub sitting at the bottom center
        Positioned(
          bottom: -WheelConstants.hubRadius * 0.4,
          child: CenterDropHub(
            controller: _controller,
            onTap: _showMediaPickerModal,
          ),
        ),
      ],
    );
  }
}
