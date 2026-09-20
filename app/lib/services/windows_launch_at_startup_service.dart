import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:win32_registry/win32_registry.dart';

import '../l10n/app_brand.dart';
import '../logger.dart';
import '../utils/windows_distribution_channel.dart';

class WindowsLaunchAtStartupService {
  WindowsLaunchAtStartupService._();

  static const startupArg = '--startup';
  static const _keyEnabled = 'ultrasend_windows_launch_at_startup';
  static String get _appName => desktopWindowTitle();
  static const _msixPackageName = 'DevUltrasend.Shrimpsend';

  static bool _configured = false;

  static bool isStartupLaunch(List<String> args) {
    return Platform.isWindows && args.contains(startupArg);
  }

  static Future<bool> getEnabledPreference() async {
    if (!Platform.isWindows) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyEnabled) ?? true;
  }

  /// Best-effort boot sync: never throws; failures are logged only.
  static Future<void> syncWithPreference() async {
    if (!Platform.isWindows) return;
    await syncWithPreferenceBestEffort(
      readPreference: getEnabledPreference,
      setSystemEnabled: _setSystemEnabled,
    );
  }

  @visibleForTesting
  static Future<void> syncWithPreferenceBestEffort({
    required Future<bool> Function() readPreference,
    required Future<void> Function(bool enabled) setSystemEnabled,
  }) async {
    try {
      final enabled = await readPreference();
      await setSystemEnabled(enabled);
    } catch (e, st) {
      logBoot.warning('windows launch at startup sync failed: $e', e, st);
    }
  }

  static Future<void> setEnabled(bool enabled) async {
    if (!Platform.isWindows) return;
    await _setSystemEnabled(enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, enabled);
  }

  static Future<void> _setSystemEnabled(bool enabled) async {
    _setup();
    if (!isWindowsMsixPackaged) {
      _ensureStartupRegistryKeys();
    }
    final success = enabled
        ? await launchAtStartup.enable()
        : await launchAtStartup.disable();
    if (!success) {
      throw StateError(
        'Failed to ${enabled ? 'enable' : 'disable'} Windows launch at startup',
      );
    }
  }

  static void _ensureStartupRegistryKeys() {
    const config = RegistryOpenConfig(access: RegistryAccess.all);
    for (final path in [
      r'Software\Microsoft\Windows\CurrentVersion\Run',
      r'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run',
    ]) {
      final key = CURRENT_USER.create(path, config: config);
      key.close();
    }
  }

  static void _setup() {
    if (_configured) return;
    launchAtStartup.setup(
      appName: _appName,
      appPath: Platform.resolvedExecutable,
      packageName: _msixPackageName,
      args: const [startupArg],
    );
    _configured = true;
  }
}
