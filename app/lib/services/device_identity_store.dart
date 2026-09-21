import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const deviceIdPreference = 'ultrasend_device_id';
const legacyDeviceSecretPreference = 'ultrasend_device_secret';
const deviceIdentityMetadataPreference = 'shrimpsend_device_identity_v2';

enum DeviceIdentityStatus { ready, storageUnavailable, recoveryRequired, restartRequired }

abstract interface class DeviceIdentityVault {
  Future<String?> read();
  Future<void> write(String value);
}

/// A public platform identifier is never an authentication credential.
class DeviceIdentity {
  const DeviceIdentity({required this.id, required this.secret, required this.scope, this.binding});
  final String id;
  final String secret;
  final String scope;
  final String? binding;

  Map<String, dynamic> toJson({bool includeSecret = true}) => {
    'version': 2,
    'id': id,
    'scope': scope,
    'binding': binding,
    if (includeSecret) 'secret': secret,
  };

  static DeviceIdentity parse(String value) {
    final data = jsonDecode(value) as Map<String, dynamic>;
    final id = data['id'];
    final secret = data['secret'];
    final scope = data['scope'];
    final binding = data['binding'];
    if (data['version'] != 2 || id is! String ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,220}$').hasMatch(id) ||
        secret is! String || secret.length < 16 || secret.length > 512 ||
        scope is! String || scope.isEmpty || scope.length > 300 ||
        (binding != null && (binding is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(binding)))) {
      throw const FormatException('Invalid device identity');
    }
    return DeviceIdentity(id: id, secret: secret, scope: scope, binding: binding as String?);
  }
}

class DeviceIdentityException implements Exception {
  const DeviceIdentityException(this.code);
  final String code;
  @override
  String toString() => 'DeviceIdentityException($code)';
}

/// One transaction-like record keeps ID and credential together. Secure writes
/// are read back before plaintext migration data is removed. A locked vault
/// must never look like a new installation or cause a credential rotation.
class DeviceIdentityStore {
  DeviceIdentityStore({
    required this.platform,
    required this.scope,
    required this.vault,
    required this.readPlatformIdentifier,
    this.namespace = '',
    Future<SharedPreferences> Function()? preferences,
  }) : _preferences = preferences ?? SharedPreferences.getInstance;

  final String platform;
  final String scope;
  final String namespace;
  final DeviceIdentityVault vault;
  final Future<String?> Function() readPlatformIdentifier;
  final Future<SharedPreferences> Function() _preferences;
  final status = ValueNotifier(DeviceIdentityStatus.ready);
  Future<DeviceIdentity>? _identity;
  Future<String?>? _binding;
  bool _restoring = false;

  String wireId(DeviceIdentity value) => namespace.isEmpty ? value.id : '${value.id}_$namespace';

  Future<String?> _getBinding() => _binding ??= (() async {
    final raw = await readPlatformIdentifier();
    if (raw == null || raw.trim().isEmpty) return null;
    return sha256.convert(utf8.encode('$scope\u0000${raw.trim()}')).toString();
  })();

  Future<DeviceIdentity> load() => _identity ??= _load().catchError((Object e) {
    _identity = null; // Allow retry after the operating system unlocks its vault.
    throw e;
  });

  Future<String> getId() async {
    try {
      return wireId(await load());
    } on DeviceIdentityException catch (e) {
      if (e.code != 'storage_unavailable') rethrow;
      // Existing local transfers can still use their public ID while the vault
      // is locked. Never create a replacement secret in this path.
      final prefs = await _preferences();
      final id = prefs.getString(deviceIdPreference);
      if (id == null || id.isEmpty) rethrow;
      return namespace.isEmpty ? id : '${id}_$namespace';
    }
  }

  Future<DeviceIdentity> _load() async {
    final prefs = await _preferences();
    final binding = await _getBinding();
    String? raw;
    try {
      raw = await vault.read();
    } catch (_) {
      status.value = DeviceIdentityStatus.storageUnavailable;
      throw const DeviceIdentityException('storage_unavailable');
    }
    DeviceIdentity? saved;
    if (raw != null) {
      try {
        saved = DeviceIdentity.parse(raw);
      } catch (_) {
        status.value = DeviceIdentityStatus.storageUnavailable;
        throw const DeviceIdentityException('storage_unavailable');
      }
      if (saved.scope != scope ||
          (binding != null && saved.binding != null && saved.binding != binding)) {
        saved = null; // A backup copied to another machine is not this device.
      }
    }

    var oldId = prefs.getString(deviceIdPreference);
    var oldSecret = prefs.getString(legacyDeviceSecretPreference);
    final metadataRaw = prefs.getString(deviceIdentityMetadataPreference);
    if (metadataRaw != null) {
      try {
        final metadata = jsonDecode(metadataRaw) as Map;
        if (metadata['scope'] != scope ||
            (binding != null && metadata['binding'] != null && metadata['binding'] != binding)) {
          oldId = null;
          oldSecret = null;
        }
      } catch (_) {
        // Do not discard the still-valid legacy pair because metadata is corrupt.
      }
    }
    // An existing ID/secret pair wins during the one-time upgrade. In normal
    // operation the complete vault record is authoritative (also after crash).
    final hasLegacyPair = oldId != null && oldId.isNotEmpty && oldSecret != null && oldSecret.length >= 16;
    final value = hasLegacyPair
        ? DeviceIdentity(id: oldId, secret: oldSecret, scope: scope, binding: binding)
        : saved != null
        ? DeviceIdentity(id: saved.id, secret: saved.secret, scope: scope, binding: saved.binding ?? binding)
        : DeviceIdentity(
            id: oldId != null && oldId.isNotEmpty
                ? oldId
                : binding != null
                ? '${platform}_v2_$binding'
                : '${platform}_uuid_${const Uuid().v4()}',
            secret: base64UrlEncode(List.generate(32, (_) => Random.secure().nextInt(256))),
            scope: scope,
            binding: binding,
          );
    await _persist(value, prefs);
    status.value = DeviceIdentityStatus.ready;
    return value;
  }

  Future<void> _persist(DeviceIdentity value, SharedPreferences prefs) async {
    final raw = jsonEncode(value.toJson());
    try {
      await vault.write(raw);
      if (await vault.read() != raw) throw StateError('Vault verification failed');
    } catch (_) {
      status.value = DeviceIdentityStatus.storageUnavailable;
      throw const DeviceIdentityException('storage_unavailable');
    }
    // Do not touch pairings, local history, device name, or account state.
    if (!await prefs.setString(deviceIdentityMetadataPreference, jsonEncode(value.toJson(includeSecret: false))) ||
        !await prefs.setString(deviceIdPreference, value.id)) {
      throw const DeviceIdentityException('preferences_unavailable');
    }
    await prefs.remove(legacyDeviceSecretPreference);
  }

  void requireRecovery() => status.value = DeviceIdentityStatus.recoveryRequired;
  void sessionVerified() {
    if (status.value == DeviceIdentityStatus.recoveryRequired) status.value = DeviceIdentityStatus.ready;
  }

  /// The backup is a private bearer credential, never a public pairing QR/code.
  Future<String> exportBackup() async {
    if (status.value == DeviceIdentityStatus.recoveryRequired ||
        status.value == DeviceIdentityStatus.restartRequired) {
      throw const DeviceIdentityException('recovery_required');
    }
    final raw = utf8.encode(jsonEncode((await load()).toJson()));
    final payload = base64UrlEncode(raw).replaceAll('=', '');
    final checksum = sha256.convert(raw).toString();
    return 'SHRIMPSEND-IDENTITY-2.$payload.$checksum';
  }

  Future<DeviceIdentity> inspectBackup(String text) async {
    try {
      if (text.length > 8192) throw const FormatException();
      final parts = text.trim().split('.');
      if (parts.length != 3 || parts.first != 'SHRIMPSEND-IDENTITY-2') throw const FormatException();
      final raw = base64Url.decode(base64Url.normalize(parts[1]));
      if (sha256.convert(raw).toString() != parts[2]) throw const FormatException();
      final value = DeviceIdentity.parse(utf8.decode(raw));
      if (value.scope != scope) throw const DeviceIdentityException('different_app');
      final binding = await _getBinding();
      if (value.binding != null && binding != null && value.binding != binding) {
        throw const DeviceIdentityException('different_device');
      }
      return value;
    } on DeviceIdentityException {
      rethrow;
    } catch (_) {
      // Do not include the input or decoder's exception (it contains secrets).
      throw const DeviceIdentityException('invalid_backup');
    }
  }

  /// Keep the running transfer identity unchanged until the next launch. This
  /// prevents a mix of old sockets, old transfer workers and a new credential.
  Future<void> restoreBackup(String text) async {
    if (_restoring || status.value == DeviceIdentityStatus.restartRequired) {
      throw const DeviceIdentityException('restart_required');
    }
    _restoring = true;
    try {
      final value = await inspectBackup(text);
      // Finish any in-flight initialization before committing the restore.
      try { await load(); } on DeviceIdentityException { /* Repair a broken vault. */ }
      await _persist(value, await _preferences());
      status.value = DeviceIdentityStatus.restartRequired;
    } finally {
      _restoring = false;
    }
  }
}
