import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/services/haptic_service.dart';
import '../../core/services/platform_channel_service.dart';

class SettingsShortcutsScreen extends StatefulWidget {
  const SettingsShortcutsScreen({super.key});

  @override
  State<SettingsShortcutsScreen> createState() => _SettingsShortcutsScreenState();
}

class _SettingsShortcutsScreenState extends State<SettingsShortcutsScreen> {
  bool _isAccessibilityEnabled = false;
  bool _isOverlayAllowed = false;
  bool _floatingDockActive = false;
  bool _hapticsEnabled = true;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final a11y = await PlatformChannelService.isAccessibilityServiceEnabled();
    final overlay = await PlatformChannelService.canDrawOverlays();
    setState(() {
      _isAccessibilityEnabled = a11y;
      _isOverlayAllowed = overlay;
      _hapticsEnabled = HapticService.enabled;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: const Text(
          'Shortcuts & System Intake',
          style: TextStyle(
            fontSize: 16.5,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary, size: 18),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        children: [
          // Section 1: Hardware Button Shortcuts
          _buildSectionHeader('HARDWARE BUTTON CHORDS'),
          _buildCard(
            child: Column(
              children: [
                _buildSwitchTile(
                  title: 'Volume Up + Down Chord',
                  subtitle: 'Hold Vol Up + Vol Down for 0.5s to inspect clipboard / screenshot and pop DropDial',
                  icon: Icons.volume_up_rounded,
                  iconColor: AppColors.dropdialOrange,
                  value: _isAccessibilityEnabled,
                  onChanged: (val) async {
                    await PlatformChannelService.openAccessibilitySettings();
                    await _checkPermissions();
                  },
                ),
                const Divider(color: AppColors.border, height: 1),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        _isAccessibilityEnabled ? Icons.check_circle : Icons.info_outline,
                        size: 16,
                        color: _isAccessibilityEnabled ? AppColors.accentGreen : AppColors.accentAmber,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _isAccessibilityEnabled
                              ? 'Accessibility Service Active & Listening'
                              : 'Tap to grant Accessibility Permission in Android Settings',
                          style: TextStyle(
                            fontSize: 11,
                            color: _isAccessibilityEnabled ? AppColors.accentGreen : AppColors.accentAmber,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // Section 2: Floating Edge Dock Overlay
          _buildSectionHeader('FLOATING EDGE DOCK (SYSTEM OVERLAY)'),
          _buildCard(
            child: Column(
              children: [
                _buildSwitchTile(
                  title: 'Floating Edge Pill Dock',
                  subtitle: 'Swipe inward from screen edge to summon DropDial over any app without leaving it',
                  icon: Icons.layers_outlined,
                  iconColor: AppColors.primaryCyan,
                  value: _floatingDockActive,
                  onChanged: (val) async {
                    if (!_isOverlayAllowed) {
                      await PlatformChannelService.openOverlaySettings();
                      await _checkPermissions();
                    } else {
                      setState(() => _floatingDockActive = val);
                      await PlatformChannelService.toggleFloatingOverlay(val);
                    }
                  },
                ),
                const Divider(color: AppColors.border, height: 1),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        _isOverlayAllowed ? Icons.check_circle : Icons.warning_amber_rounded,
                        size: 16,
                        color: _isOverlayAllowed ? AppColors.accentGreen : AppColors.accentAmber,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _isOverlayAllowed
                              ? 'Overlay Permission Granted (SYSTEM_ALERT_WINDOW)'
                              : 'Requires "Display Over Other Apps" permission',
                          style: TextStyle(
                            fontSize: 11,
                            color: _isOverlayAllowed ? AppColors.accentGreen : AppColors.accentAmber,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // Section 3: Quick Settings Tile
          _buildSectionHeader('ANDROID QUICK SETTINGS TILE'),
          _buildCard(
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.accentPurple.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.dashboard_customize_rounded, color: AppColors.accentPurple, size: 20),
              ),
              title: const Text('Quick Settings DropDial Tile', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13.5)),
              subtitle: const Text(
                'Pull down notification shade -> Tap Edit -> Drag "DropDial" into active tiles for instant 1-tap dial access.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
              ),
            ),
          ),

          const SizedBox(height: 18),

          // Section 4: System Share Sheet
          _buildSectionHeader('SYSTEM SHARE SHEET (ZERO CONFIG)'),
          _buildCard(
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.accentGreen.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.share_rounded, color: AppColors.accentGreen, size: 20),
              ),
              title: const Text('Direct Share Intake', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 13.5)),
              subtitle: const Text(
                'Open any file in WhatsApp, Gallery, Files, or Browser -> Tap Share -> Select DropDial. The semi-circle dial blooms automatically.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
              ),
            ),
          ),

          const SizedBox(height: 18),

          // Section 5: Preferences & Haptics
          _buildSectionHeader('PHYSICAL FEEDBACK & HAPTICS'),
          _buildCard(
            child: _buildSwitchTile(
              title: 'Rotary Haptic Detents',
              subtitle: 'Mechanical tick on every petal crossing and magnetic snap',
              icon: Icons.vibration_rounded,
              iconColor: AppColors.dropdialOrange,
              value: _hapticsEnabled,
              onChanged: (val) {
                setState(() {
                  _hapticsEnabled = val;
                  HapticService.enabled = val;
                });
              },
            ),
          ),

          const SizedBox(height: 22),

          // Privacy Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: const Row(
              children: [
                Icon(Icons.shield_rounded, color: AppColors.accentGreen, size: 28),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '100% Offline Architecture',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Zero cloud uploads. Zero telemetry. All conversions happen strictly on-device using local machine code.',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      activeThumbColor: AppColors.dropdialOrange,
      secondary: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.bold,
          fontSize: 13.5,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 11.5,
        ),
      ),
    );
  }
}
