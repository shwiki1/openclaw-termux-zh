import 'package:flutter/material.dart';

import '../app.dart';
import '../l10n/app_localizations.dart';
import '../services/native_bridge.dart';
import 'open_source_licenses_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  bool _loading = true;
  bool _batteryOptimized = true;
  bool _storageGranted = false;
  bool _overlayGranted = false;
  bool _floatingFileManagerRunning = false;
  bool _waitingBatteryOptimizationReturn = false;
  int _batteryOptimizationRefreshToken = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _refreshPermissionState();
      if (_waitingBatteryOptimizationReturn) {
        _waitingBatteryOptimizationReturn = false;
        _refreshBatteryOptimizationAfterSettings();
      }
    }
  }

  Future<void> _loadSettings() async {
    try {
      await _refreshPermissionState(updateLoading: false);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _refreshPermissionState({bool updateLoading = true}) async {
    try {
      final batteryOptimized = await NativeBridge.isBatteryOptimized();
      final storageGranted = await NativeBridge.hasStoragePermission();
      final overlayGranted = await NativeBridge.hasOverlayPermission();
      final floatingFileManagerRunning =
          await NativeBridge.isFloatingFileManagerRunning();
      if (!mounted) return;
      setState(() {
        _batteryOptimized = batteryOptimized;
        _storageGranted = storageGranted;
        _overlayGranted = overlayGranted;
        _floatingFileManagerRunning = floatingFileManagerRunning;
        if (updateLoading) {
          _loading = false;
        }
      });
    } catch (_) {
      if (mounted && updateLoading) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _refreshBatteryOptimizationAfterSettings() async {
    final token = ++_batteryOptimizationRefreshToken;
    const delays = <Duration>[
      Duration.zero,
      Duration(milliseconds: 250),
      Duration(milliseconds: 500),
      Duration(milliseconds: 900),
      Duration(milliseconds: 1400),
      Duration(seconds: 2),
      Duration(seconds: 3),
      Duration(seconds: 4),
    ];

    for (final delay in delays) {
      if (delay > Duration.zero) {
        await Future<void>.delayed(delay);
      }
      if (token != _batteryOptimizationRefreshToken || !mounted) return;
      try {
        final optimized = await NativeBridge.isBatteryOptimized();
        if (token != _batteryOptimizationRefreshToken || !mounted) return;
        if (_batteryOptimized != optimized) {
          setState(() => _batteryOptimized = optimized);
        }
        if (!optimized) return;
      } catch (_) {
        return;
      }
    }
  }

  Future<void> _openOpenSourceLicenses() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const OpenSourceLicensesScreen()),
    );
  }

  Future<void> _requestBatteryOptimization() async {
    _waitingBatteryOptimizationReturn = true;
    await NativeBridge.requestBatteryOptimization();
    if (!mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await _refreshBatteryOptimizationAfterSettings();
  }

  Future<void> _requestStoragePermission() async {
    final l10n = context.l10n;
    final shouldRequest = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.t('settingsStorageDialogTitle')),
        content: Text(l10n.t('settingsStorageDialogBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.t('commonCancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.t('settingsStorageDialogAction')),
          ),
        ],
      ),
    );
    if (shouldRequest != true) return;

    bool granted;
    try {
      granted = await NativeBridge.requestStoragePermission();
    } catch (_) {
      granted = await NativeBridge.hasStoragePermission();
    }
    if (!mounted) return;
    setState(() => _storageGranted = granted);
  }

  Future<void> _setFloatingFileManagerRunning(bool value) async {
    if (value) {
      var granted = await NativeBridge.hasOverlayPermission();
      if (!granted) {
        await NativeBridge.requestOverlayPermission();
        granted = await NativeBridge.hasOverlayPermission();
      }
      if (!mounted) return;
      if (!granted) {
        setState(() => _overlayGranted = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.t('settingsFloatingFileManagerPermissionMissing')),
          ),
        );
        return;
      }
      await NativeBridge.startFloatingFileManager();
    } else {
      await NativeBridge.stopFloatingFileManager();
    }

    final running = await NativeBridge.isFloatingFileManagerRunning();
    final overlay = await NativeBridge.hasOverlayPermission();
    if (!mounted) return;
    setState(() {
      _overlayGranted = overlay;
      _floatingFileManagerRunning = running;
    });
  }

  Widget _sectionHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(
        title,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('settingsTitle'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _sectionHeader(theme, l10n.t('settingsSystemAccess')),
                ListTile(
                  title: Text(l10n.t('settingsBatteryOptimization')),
                  subtitle: Text(
                    _batteryOptimized
                        ? l10n.t('settingsBatteryOptimized')
                        : l10n.t('settingsBatteryUnrestricted'),
                  ),
                  leading: const Icon(Icons.battery_alert),
                  trailing: _batteryOptimized
                      ? const Icon(Icons.warning, color: AppColors.statusAmber)
                      : const Icon(
                          Icons.check_circle,
                          color: AppColors.statusGreen,
                        ),
                  onTap: _requestBatteryOptimization,
                ),
                ListTile(
                  title: Text(l10n.t('settingsStorage')),
                  subtitle: Text(
                    _storageGranted
                        ? l10n.t('settingsStorageGranted')
                        : l10n.t('settingsStorageMissing'),
                  ),
                  leading: const Icon(Icons.sd_storage),
                  trailing: _storageGranted
                      ? const Icon(
                          Icons.check_circle,
                          color: AppColors.statusGreen,
                        )
                      : const Icon(Icons.warning, color: AppColors.statusAmber),
                  onTap: _requestStoragePermission,
                ),
                SwitchListTile(
                  title: Text(l10n.t('settingsFloatingFileManager')),
                  subtitle: Text(
                    _overlayGranted
                        ? l10n.t('settingsFloatingFileManagerSubtitle')
                        : l10n.t('settingsFloatingFileManagerPermissionSubtitle'),
                  ),
                  secondary: const Icon(Icons.folder_copy_outlined),
                  value: _floatingFileManagerRunning,
                  onChanged: _setFloatingFileManagerRunning,
                ),
                _sectionHeader(theme, l10n.t('settingsLicense')),
                ListTile(
                  leading: const Icon(Icons.policy_outlined),
                  title: Text(l10n.t('settingsOpenSourceLicenses')),
                  subtitle: Text(l10n.t('settingsOpenSourceLicensesSubtitle')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openOpenSourceLicenses,
                ),
              ],
            ),
    );
  }
}
