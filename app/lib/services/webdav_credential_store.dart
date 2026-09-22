import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/webdav.dart';

const _storageKeyPrefix = 'webdav_cred_';
const _indexKey = 'webdav_cached_connection_ids';

abstract interface class WebDavSecureStorage {
  Future<String?> read({required String key});
  Future<void> write({required String key, required String value});
  Future<void> delete({required String key});
  Future<void> deleteAll();
}

class FlutterWebDavSecureStorage implements WebDavSecureStorage {
  FlutterWebDavSecureStorage([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // Desktop distribution does not use Keychain Sharing or an App Group.
            // The macOS login Keychain works without a provisioning profile.
            mOptions: MacOsOptions(usesDataProtectionKeychain: false),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read({required String key}) => _storage.read(key: key);

  @override
  Future<void> write({required String key, required String value}) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete({required String key}) => _storage.delete(key: key);

  @override
  Future<void> deleteAll() => _storage.deleteAll();
}

/// Session cache for WebDAV credentials. Never use SharedPreferences/sqflite.
class WebDavCredentialStore {
  WebDavCredentialStore._({WebDavSecureStorage? secure})
    : _secure = secure ?? FlutterWebDavSecureStorage();

  static final WebDavCredentialStore instance = WebDavCredentialStore._();

  @visibleForTesting
  factory WebDavCredentialStore.forTesting(WebDavSecureStorage secure) {
    return WebDavCredentialStore._(secure: secure);
  }

  final WebDavSecureStorage _secure;
  final Map<int, WebDavCredentials> _memory = {};

  WebDavCredentials? getFromMemory(int connectionId) => _memory[connectionId];

  Future<WebDavCredentials?> read(int connectionId) async {
    final cached = _memory[connectionId];
    if (cached != null) return cached;

    final raw = await _readSecure('$_storageKeyPrefix$connectionId');
    if (raw == null || raw.isEmpty) return null;
    try {
      final creds = WebDavCredentials.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      _memory[connectionId] = creds;
      return creds;
    } catch (_) {
      await _deleteSecure('$_storageKeyPrefix$connectionId');
      return null;
    }
  }

  Future<void> write(int connectionId, WebDavCredentials creds) async {
    _memory[connectionId] = creds;
    final rawIds = await _readSecure(_indexKey);
    final ids = <int>{..._memory.keys};
    try {
      ids.addAll((jsonDecode(rawIds ?? '[]') as List).cast<int>());
    } catch (_) {}
    await _writeSecure(_indexKey, jsonEncode(ids.toList()));
    await _writeSecure(
      '$_storageKeyPrefix$connectionId',
      jsonEncode(creds.toJson()),
    );
  }

  Future<void> remove(int connectionId) async {
    _memory.remove(connectionId);
    await _deleteSecure('$_storageKeyPrefix$connectionId');
  }

  Future<void> wipeAll() async {
    final ids = <int>{..._memory.keys};
    try {
      ids.addAll(
        (jsonDecode(await _readSecure(_indexKey) ?? '[]') as List).cast<int>(),
      );
    } catch (_) {}
    _memory.clear();
    for (final id in ids) {
      await _deleteSecure('$_storageKeyPrefix$id');
    }
    await _deleteSecure(_indexKey);
  }

  Future<String?> _readSecure(String key) async {
    try {
      return await _secure.read(key: key);
    } on PlatformException catch (e) {
      _logSecureStorageError('read', e);
      return null;
    }
  }

  Future<void> _writeSecure(String key, String value) async {
    try {
      await _secure.write(key: key, value: value);
    } on PlatformException catch (e) {
      _logSecureStorageError('write', e);
    }
  }

  Future<void> _deleteSecure(String key) async {
    try {
      await _secure.delete(key: key);
    } on PlatformException catch (e) {
      _logSecureStorageError('delete', e);
    }
  }

  void _logSecureStorageError(String operation, PlatformException error) {
    debugPrint(
      'WebDavCredentialStore: secure storage $operation failed '
      '(${error.code}): ${error.message}',
    );
  }
}

String redactWebDavSecrets(String message) {
  var out = message;
  out = out.replaceAll(RegExp(r'://[^:@/]+:[^@/]+@'), '://***:***@');
  return out;
}
