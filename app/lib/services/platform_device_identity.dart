import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mobile_device_identifier/mobile_device_identifier.dart';

import 'device_identity_store.dart';

/// Identifiers are scoped again by package + deployment namespace in the store.
/// They identify a device; they never provide proof of possession by themselves.
Future<String?> readPlatformDeviceIdentifier() async {
  try {
    final info = DeviceInfoPlugin();
    String? value;
    if (Platform.isAndroid) {
      value = await const MethodChannel('dev.ultrasend/device_identity')
          .invokeMethod<String>('getAndroidId');
      if (value == '9774d56d682e549c' || value == '0000000000000000') return null;
    } else if (Platform.isIOS) {
      value = await MobileDeviceIdentifier().getDeviceId();
    } else if (Platform.isMacOS) {
      value = (await info.macOsInfo).systemGUID;
    } else if (Platform.isWindows) {
      value = (await info.windowsInfo).deviceId;
    } else if (Platform.isLinux) {
      value = (await info.linuxInfo).machineId;
    }
    if (value == null || value.trim().isEmpty) return null;
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      // Separate OS users must not share one credential on the same computer.
      value = '$value\u0000${Platform.environment['USER'] ?? Platform.environment['USERNAME'] ?? ''}';
    }
    return value;
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}

class SecureDeviceIdentityVault implements DeviceIdentityVault {
  SecureDeviceIdentityVault(String scope)
      : _key = 'shrimpsend_device_identity_v2_$scope',
        _storage = const FlutterSecureStorage(
          // This store has separate Android keys from WebDAV/login credentials.
          aOptions: AndroidOptions(storageNamespace: 'shrimpsend_identity', resetOnError: false),
          iOptions: IOSOptions(
            accountName: 'shrimpsend_device_identity',
            accessibility: KeychainAccessibility.first_unlock_this_device,
            synchronizable: false,
          ),
          // Our macOS distribution has no provisioning profile/App Group.
          mOptions: MacOsOptions(
            accountName: 'shrimpsend_device_identity',
            usesDataProtectionKeychain: false,
            synchronizable: false,
          ),
        );

  final String _key;
  final FlutterSecureStorage _storage;
  @override
  Future<String?> read() => _storage.read(key: _key);
  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);
}
