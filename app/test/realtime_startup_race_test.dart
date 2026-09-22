import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:app/api/realtime_token.dart';
import 'package:app/services/realtime_hub.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'resume and connectivity during handshake keep the initial socket',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv6, 0);
      final handshake = Completer<void>();
      final release = Completer<void>();
      final sockets = <WebSocket>[];
      server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket.listen((raw) async {
          final frame = jsonDecode(raw as String) as Map;
          if (frame['method'] != 'connect') return;
          if (!handshake.isCompleted) handshake.complete();
          await release.future;
          socket.add(
            jsonEncode({
              'id': frame['id'],
              'result': {'reasonCode': 1},
            }),
          );
        });
      });
      final hub = RealtimeHub(
        tokenFetcher: ({required deviceId, required platform}) async =>
            RealtimeTokenResponse(
              uid: deviceId,
              token: 'test',
              websocketUrl: 'ws://[::1]:${server.port}',
              deviceFlag: 0,
              deviceLevel: 1,
              channelId: deviceId,
              channelType: 1,
            ),
        mailboxFetcher: ({required deviceId, afterId = 0}) async => [],
      );
      try {
        final start = hub.start(deviceId: 'startup-race', deviceName: 'Test');
        await handshake.future.timeout(const Duration(seconds: 5));
        await hub.onAppResumed();
        await hub.onConnectivityChanged();
        release.complete();
        await start;
        expect(hub.isConnected, isTrue);
        expect(sockets, hasLength(1));
      } finally {
        if (!release.isCompleted) release.complete();
        await hub.dispose();
        for (final socket in sockets) {
          await socket.close();
        }
        await server.close(force: true);
      }
    },
  );
}
