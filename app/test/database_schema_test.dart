import 'package:app/services/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'fresh schema creates indexes; an existing WebDAV table survives upgrade',
    () async {
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      addTearDown(db.close);
      await AppDatabase.instance.createSchema(db);
      await db.insert('webdav_favorites', {
        'connection_id': 'test',
        'remote_path': '/keep',
        'name': 'keep',
        'created_at': DateTime.now().toIso8601String(),
      });
      await db.insert('chat_messages', {
        'id': 'keep',
        'user_id': 'old',
        'type': 'text',
        'payload': '{}',
        'from_device_id': 'peer',
        'ts': 1,
        'thread_key': 'u:42|d1:a|d2:b',
      });
      await AppDatabase.instance.upgradeSchema(db, 7);
      expect(
        (await db.query('chat_messages')).single['thread_key'],
        'device|d1:a|d2:b',
      );
      expect(await db.query('webdav_favorites'), hasLength(1));
      final indexes = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index'",
      );
      expect(
        indexes.map((r) => r['name']),
        containsAll([
          'idx_transfer_status',
          'idx_msg_user_thread_ts',
          'idx_recv_mtime',
          'idx_webdav_recent_conn_time',
        ]),
      );
    },
  );
}
