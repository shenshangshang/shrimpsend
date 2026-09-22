import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/webdav.dart';
import 'webdav_credential_store.dart';

/// Device-owned connections use negative IDs; existing account connections retain
/// their positive server IDs. Secrets remain in the operating system keychain.
class LocalWebDavConnections {
  LocalWebDavConnections({WebDavSecureStorage? secure})
    : _secure = secure ?? FlutterWebDavSecureStorage();
  static final instance = LocalWebDavConnections();
  static const _key = 'product.localWebDavConnections';
  final WebDavSecureStorage _secure;
  Future<void> _pendingWrite = Future.value();
  Future<List<WebDavConnectionSummary>> list() async {
    final prefs = await SharedPreferences.getInstance();
    return ((jsonDecode(prefs.getString(_key) ?? '[]')) as List)
        .map(
          (row) => WebDavConnectionSummary.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList();
  }

  Future<WebDavConnectionSummary> get(int id) async =>
      (await list()).firstWhere(
        (row) => row.id == id,
        orElse: () => throw StateError('连接不存在'),
      );
  Future<WebDavCredentials> credentials(int id) async {
    final raw = await _secure.read(key: 'product_local_dav_$id');
    if (raw == null) throw StateError('请编辑连接并重新输入密码');
    return WebDavCredentials.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<WebDavConnectionSummary> save(
    WebDavConnectionRequest req, {
    int? id,
  }) async {
    final previous = _pendingWrite;
    final result = previous.then((_) => _save(req, id));
    _pendingWrite = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  Future<WebDavConnectionSummary> _save(
    WebDavConnectionRequest req,
    int? id,
  ) async {
    final uri = Uri.tryParse(req.baseUrl.trim());
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment)
      throw const FormatException('请输入有效的 WebDAV 地址，不要在地址中包含密码');
    final rows = await list();
    final identifier = id ?? -(DateTime.now().microsecondsSinceEpoch);
    final old = id == null || req.password?.isNotEmpty == true
        ? null
        : await credentials(id);
    final secret = WebDavCredentials(
      username: req.username ?? old?.username ?? '',
      password: req.password?.isNotEmpty == true
          ? req.password!
          : old?.password ?? '',
      baseUrl: uri.toString(),
      rootPath: req.rootPath ?? '/',
      clientApp: req.clientApp,
    );
    await _secure.write(
      key: 'product_local_dav_$identifier',
      value: jsonEncode(secret.toJson()),
    );
    final result = WebDavConnectionSummary(
      id: identifier,
      name: req.name.trim(),
      baseUrl: uri.toString(),
      rootPath: req.rootPath ?? '/',
      clientApp: req.clientApp,
      updatedAt: DateTime.now(),
    );
    await _writeRows([...rows.where((row) => row.id != identifier), result]);
    return result;
  }

  Future<void> remove(int id) async {
    final previous = _pendingWrite;
    final result = previous.then((_) async {
      await _writeRows((await list()).where((row) => row.id != id).toList());
      await _secure.delete(key: 'product_local_dav_$id');
    });
    _pendingWrite = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  Future<void> _writeRows(List<WebDavConnectionSummary> rows) async {
    final prefs = await SharedPreferences.getInstance();
    final ok = await prefs.setString(
      _key,
      jsonEncode(
        rows
            .map(
              (row) => {
                'id': row.id,
                'name': row.name,
                'baseUrl': row.baseUrl,
                'rootPath': row.rootPath,
                'clientApp': row.clientApp,
                'updatedAt': row.updatedAt?.toIso8601String(),
              },
            )
            .toList(),
      ),
    );
    if (!ok) throw StateError('无法保存连接，请重试');
  }
}
