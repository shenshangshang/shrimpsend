import 'dart:convert';
import 'package:app/api/webdav.dart';
import 'package:app/services/local_webdav_connections.dart';
import 'package:app/services/webdav_credential_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Secure implements WebDavSecureStorage {
  final values = <String, String>{};
  bool fail = false;
  @override Future<String?> read({required String key}) async => values[key];
  @override Future<void> write({required String key, required String value}) async { if (fail) throw StateError('keychain unavailable'); values[key] = value; }
  @override Future<void> delete({required String key}) async => values.remove(key);
  @override Future<void> deleteAll() async => values.clear();
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('device connection survives account credential cleanup and keeps secrets out of preferences', () async {
    final secure = _Secure();
    final store = LocalWebDavConnections(secure: secure);
    final row = await store.save(const WebDavConnectionRequest(name: 'NAS', baseUrl: 'http://localhost:4318/dav/', username: 'qa', password: 'private-fixture'));
    expect(row.id, lessThan(0));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('product.localWebDavConnections'), isNot(contains('private-fixture')));
    final accountStore = WebDavCredentialStore.forTesting(secure);
    await accountStore.write(1, const WebDavCredentials(username: 'account', password: 'cached', baseUrl: 'https://example.com', rootPath: '/'));
    secure.values['unrelated'] = 'keep';
    await accountStore.wipeAll();
    expect(secure.values['unrelated'], 'keep');
    expect((await store.credentials(row.id)).password, 'private-fixture');
    final saved = await store.save(const WebDavConnectionRequest(name: 'Renamed', baseUrl: 'http://localhost:4318/dav/', username: 'qa'), id: row.id);
    expect(saved.name, 'Renamed');
    expect((await store.credentials(row.id)).password, 'private-fixture');
    await store.remove(row.id);
    expect(await store.list(), isEmpty);
    expect(secure.values.keys.where((key) => key.startsWith('product_local_dav_')), isEmpty);
  });
  test('concurrent additions do not overwrite each other and reject unsafe URL credentials', () async {
    final store = LocalWebDavConnections(secure: _Secure());
    await Future.wait(List.generate(4, (index) => store.save(WebDavConnectionRequest(name: '$index', baseUrl: 'https://example.com/dav', password: 'secret'))));
    expect(await store.list(), hasLength(4));
    expect((await store.list()).map((row) => row.id).toSet(), hasLength(4));
    await expectLater(store.save(const WebDavConnectionRequest(name: 'Invalid', baseUrl: 'https://user:password@example.com')), throwsFormatException);
  });
  test('keychain failure cannot report a persisted connection', () async {
    final secure = _Secure()..fail = true;
    final store = LocalWebDavConnections(secure: secure);
    await expectLater(store.save(const WebDavConnectionRequest(name: 'NAS', baseUrl: 'https://example.com', password: 'secret')), throwsStateError);
    expect(jsonDecode((await SharedPreferences.getInstance()).getString('product.localWebDavConnections') ?? '[]'), isEmpty);
  });
}
