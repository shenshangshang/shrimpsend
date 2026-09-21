import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:app/services/wukongim_jsonrpc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'real socket acknowledges delivery and pong does not reconnect',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final received = Completer<Map<String, dynamic>>();
      final acknowledged = Completer<Map<String, dynamic>>();
      int connections = 0;
      server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen((raw) {
          final frame = jsonDecode(raw as String) as Map<String, dynamic>;
          if (frame['method'] == 'connect') {
            socket.add(
              jsonEncode({
                'id': frame['id'],
                'result': {'reasonCode': 1},
              }),
            );
            socket.add(jsonEncode({'id': 'unrelated-ping', 'result': {}}));
            socket.add(
              jsonEncode({
                'method': 'recv',
                'params': {
                  'messageId': '9007199254740999',
                  'messageSeq': 12,
                  'payload': {'type': 'text'},
                },
              }),
            );
          } else if (frame['method'] == 'recvack' &&
              !acknowledged.isCompleted) {
            acknowledged.complete(
              Map<String, dynamic>.from(frame['params'] as Map),
            );
          }
        });
      });
      final client = WukongimJsonRpcClient(
        websocketUrl: 'ws://127.0.0.1:${server.port}',
        uid: 'local-test',
        token: 'test-only',
        deviceId: 'test-device',
        deviceFlag: 2,
        onMessage: (message) {
          if (!received.isCompleted) received.complete(message);
        },
        onConnected: () => connections++,
      );
      try {
        await client.connect();
        await received.future.timeout(const Duration(seconds: 5));
        final ack = await acknowledged.future.timeout(
          const Duration(seconds: 5),
        );
        expect(ack, {'messageId': '9007199254740999', 'messageSeq': 12});
        expect(connections, 1);
      } finally {
        await client.disconnect();
        await server.close(force: true);
      }
    },
  );
  test('unwraps type 200 envelope from base64 payload', () {
    final wrapped = jsonEncode({
      'type': 200,
      'v': 1,
      'envelope': {'type': 'text', 'fromDeviceId': 'a'},
    });
    final params = {'payload': base64Encode(utf8.encode(wrapped))};
    final envelope = unwrapWukongimParams(params);
    expect(envelope?['type'], 'text');
    expect(envelope?['fromDeviceId'], 'a');
  });

  test('unwraps legacy string-typed envelope', () {
    final envelope = unwrapWukongimParams({
      'payload': {'type': 'webrtc_offer', 'fromDeviceId': 'b'},
    });
    expect(envelope?['type'], 'webrtc_offer');
  });

  test('returns null for unknown payload', () {
    expect(unwrapWukongimParams({'payload': 'nope'}), isNull);
  });
}
