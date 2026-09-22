import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'utils/runtime_platform.dart';
import 'services/device_identity_store.dart';
import 'services/platform_device_identity.dart';

const _keyDeviceName = 'ultrasend_device_name';
const pendingDeviceNameKey = 'shrimpsend_pending_device_name';
final deviceNameChanges = StreamController<String>.broadcast();

String get _platformPrefix {
  if (kIsWeb) return 'web';
  return RuntimePlatform.osName;
}

Future<DeviceIdentityStore>? _identityStoreFuture;
Future<DeviceIdentityStore> getDeviceIdentityStore() =>
    _identityStoreFuture ??= _createIdentityStore();

Future<DeviceIdentityStore> _createIdentityStore() async {
  final package = await PackageInfo.fromPlatform();
  const namespace = String.fromEnvironment('DEVICE_ID_NAMESPACE');
  final scope = '${package.packageName}:$namespace';
  return DeviceIdentityStore(
    platform: _platformPrefix,
    scope: scope,
    namespace: namespace,
    vault: SecureDeviceIdentityVault(scope),
    readPlatformIdentifier: readPlatformDeviceIdentifier,
  );
}

Future<String> _generateDeviceName() async {
  final info = DeviceInfoPlugin();
  try {
    if (Platform.isAndroid) {
      final android = await info.androidInfo;
      final brand = android.brand;
      final model = android.model;
      final capitalizedBrand = brand.isEmpty
          ? ''
          : brand[0].toUpperCase() + brand.substring(1);
      return '$capitalizedBrand $model'.trim();
    } else if (Platform.isIOS) {
      final ios = await info.iosInfo;
      return ios.name;
    } else if (Platform.isMacOS) {
      final mac = await info.macOsInfo;
      return mac.computerName;
    } else if (Platform.isWindows) {
      final win = await info.windowsInfo;
      return win.computerName;
    } else if (Platform.isLinux) {
      final linux = await info.linuxInfo;
      return linux.prettyName;
    } else if (RuntimePlatform.isOhos) {
      try {
        final data = (await info.deviceInfo).data;
        final brand = '${data['brand'] ?? data['manufacture'] ?? ''}'.trim();
        final model =
            '${data['marketName'] ?? data['productModel'] ?? data['model'] ?? ''}'
                .trim();
        final name = '$brand $model'.trim();
        if (name.isNotEmpty) return name;
      } catch (_) {}
      return 'HarmonyOS';
    }
  } catch (_) {
    // fall through to default
  }
  return _platformPrefix;
}

bool _isLegacyDeviceName(String name) {
  return name == 'Flutter';
}

Future<String> getOrCreateDeviceSecret() async {
  final store = await getDeviceIdentityStore();
  if (store.status.value == DeviceIdentityStatus.restartRequired) {
    throw const DeviceIdentityException('restart_required');
  }
  return (await store.load()).secret;
}

Future<String>? _deviceIdFuture;
Future<String> getOrCreateDeviceId() => _deviceIdFuture ??=
    getDeviceIdentityStore().then((store) => store.getId()).catchError((Object error) {
      _deviceIdFuture = null;
      throw error;
    });

Future<String> getDeviceName() async {
  final prefs = await SharedPreferences.getInstance();
  var name = prefs.getString(_keyDeviceName);
  if (name == null || name.isEmpty || _isLegacyDeviceName(name)) {
    name = await _generateDeviceName();
    await prefs.setString(_keyDeviceName, name);
  }
  return name;
}

Future<void> setDeviceName(String name) async {
  final prefs = await SharedPreferences.getInstance();
  final value = name.trim();
  if (value.isEmpty ||
      value.length > 80 ||
      RegExp(r'[\x00-\x1f\x7f-\x9f]').hasMatch(value))
    throw ArgumentError('Invalid device name');
  await prefs.setString(_keyDeviceName, value);
  await prefs.setString(pendingDeviceNameKey, value);
  deviceNameChanges.add(value);
}

/// 登录/注册 API 的 `platform` 字段；Web 多台浏览器在后端计 1 台设备。
Future<String> getAuthPlatformLabel() async {
  if (kIsWeb) return 'web';
  return _platformPrefix;
}
