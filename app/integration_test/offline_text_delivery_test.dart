import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/api/devices.dart';
import 'package:app/chat/thread_key.dart';
import 'package:app/device_id.dart';
import 'package:app/main.dart' as app;
import 'package:app/providers/auth_provider.dart';
import 'package:app/providers/device_provider.dart';
import 'package:app/providers/realtime_hub_provider.dart';
import 'package:app/services/chat_message_dao.dart';
import 'package:app/services/database.dart';
import 'package:app/ui/product_workspace.dart';
import 'package:app/widgets/chat/chat_composer.dart';
import 'package:app/widgets/chat/chat_message_bubbles.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('offline native text send, failed bubble retry and replay', (
    tester,
  ) async {
    app.main([]);
    Future<void> waitFor(
      FutureOr<bool> Function() ready, {
      int seconds = 45,
    }) async {
      final end = DateTime.now().add(Duration(seconds: seconds));
      while (DateTime.now().isBefore(end)) {
        if (await ready()) return;
        await tester.pump(const Duration(milliseconds: 150));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(await ready(), isTrue);
    }

    await waitFor(() => find.byType(ProductWorkspace).evaluate().isNotEmpty);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ProductWorkspace)),
    );
    expect(container.read(authProvider).isLoggedIn, isFalse);
    expect(
      container.read(realtimeHubProvider).isConnected,
      isFalse,
      reason: 'Run with API and signaling unreachable',
    );
    const url = String.fromEnvironment(
      'TEXT_QA_PEER_URL',
      defaultValue: 'http://192.168.0.100:9080',
    );
    final info =
        jsonDecode((await http.get(Uri.parse('$url/device-info'))).body) as Map;
    final peer = info['deviceId'] as String;
    final me = await getOrCreateDeviceId();
    final userId = await getOrCreateOfflineUserId();
    final thread = threadKeyOneToOne(accountPartOffline(userId), me, peer);
    final run = DateTime.now().millisecondsSinceEpoch.toString();
    final retryId = 'offline-retry-$run';
    // Load a failed outgoing text through the same persisted history as an
    // interrupted user send, then tap its actual retry control.
    container.read(selectedDeviceIdProvider.notifier).select(null);
    await tester.pump(const Duration(milliseconds: 300));
    await ChatMessageDao.instance.insertMessage(
      userId: userId,
      id: 'local_$retryId',
      type: 'text',
      payload: {'text': 'OFFLINE-TEXT-$run retry 重试 🦐', 'localId': retryId},
      fromDeviceId: me,
      ts: DateTime.now().millisecondsSinceEpoch,
      threadKey: thread,
      synced: false,
      status: 'failed',
    );
    container
        .read(pairedPeersProvider.notifier)
        .upsert(
          DeviceDto(
            deviceId: peer,
            name: info['name'] as String,
            platform: info['platform'] as String?,
            lanHttpUrl: url,
          ),
        );
    container.read(selectedDeviceIdProvider.notifier).select(peer);
    final failed = find.byWidgetPredicate(
      (widget) =>
          widget is FailedTextBubble && widget.message.id == 'local_$retryId',
    );
    await waitFor(() => failed.evaluate().isNotEmpty);
    await tester.tap(
      find.descendant(of: failed, matching: find.byIcon(LucideIcons.refreshCw)),
    );
    await waitFor(
      () async =>
          (await ChatMessageDao.instance.getById('local_$retryId'))?.status ==
          'sent',
    );

    final texts = [
      'OFFLINE-TEXT-$run 中文、English、emoji 🦐',
      'OFFLINE-TEXT-$run 第一行\n第二行\n第三行',
      'OFFLINE-TEXT-$run ${List.filled(300, '长文本验证 ').join()}',
    ];
    for (final text in texts) {
      final composer = find.byType(ChatComposer);
      await tester.enterText(
        find.descendant(of: composer, matching: find.byType(TextField)),
        text,
      );
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tap(
        find.descendant(of: composer, matching: find.byType(FilledButton)).last,
      );
      await waitFor(() async {
        final rows = await AppDatabase.instance.db.query(
          'chat_messages',
          where: 'from_device_id = ? AND type = ?',
          whereArgs: [me, 'text'],
          orderBy: 'ts DESC',
          limit: 10,
        );
        return rows.any(
          (row) =>
              jsonDecode(row['payload'] as String)['text'] == text.trim() &&
              row['status'] == 'sent',
        );
      });
    }
    final records =
        (await AppDatabase.instance.db.query(
              'chat_messages',
              where: 'from_device_id = ? AND type = ?',
              whereArgs: [me, 'text'],
              orderBy: 'ts DESC',
              limit: 20,
            ))
            .where(
              (row) => (jsonDecode(row['payload'] as String)['text'] as String)
                  .startsWith('OFFLINE-TEXT-$run'),
            )
            .toList();
    expect(records.length, 4);
    // Replay the same message twice to the real receiver. The host verifies
    // the receiver database has exactly one matching row per test text.
    final row = records.first;
    final payload = jsonDecode(row['payload'] as String) as Map;
    for (var i = 0; i < 2; i++) {
      final response = await http.post(
        Uri.parse('$url/message'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode({
          'text': payload['text'],
          'textId': payload['localId'],
          'localId': payload['localId'],
          'ts': row['ts'],
          'fromDeviceId': me,
          'toDeviceId': peer,
        }),
      );
      expect(response.statusCode, 200);
    }
    await tester.pump(const Duration(seconds: 1));
    expect(container.read(realtimeHubProvider).isConnected, isFalse);
    expect(tester.takeException(), isNull);
    final result = {
      'run': run,
      'sender': me,
      'peer': peer,
      'sent': 4,
      'serverConnected': false,
      'retryId': retryId,
    };
    final output = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/text-qa',
    );
    await output.create(recursive: true);
    await File('${output.path}/result.json').writeAsString(jsonEncode(result));
    // ignore: avoid_print
    print('OFFLINE_TEXT_RESULT ${jsonEncode(result)}');
  });
}
