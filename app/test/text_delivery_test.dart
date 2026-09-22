import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/api/messages.dart';
import 'package:app/lan/transfer_worker.dart';
import 'package:app/services/text_delivery.dart';
import 'package:app/utils/helpers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final envelope = <String, dynamic>{
    'type': 'text',
    'payload': {'text': '中文换行\n🦐 text', 'localId': 'one', 'textId': 'one'},
    'fromDeviceId': 'phone',
    'toDeviceId': 'desktop',
    'ts': 123,
  };

  test('real LAN receiver forwards identity and rejects the wrong recipient', () async {
    final directory = await Directory.systemTemp.createTemp('text-delivery-');
    final probe = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = probe.port;
    await probe.close();
    final received = Completer<Map<String, Object?>>();
    var arrivals = 0;
    final server = HttpTransferServer(
      onFileReceived: (_, __, ___, {messageId, senderLocalId, lastModifiedMs}) {},
      onMessageReceived: (text, from, name, {localId, ts}) {
        arrivals++;
        received.complete({'text': text, 'from': from, 'id': localId, 'ts': ts});
      },
    );
    addTearDown(() async {
      await server.stop();
      await directory.delete(recursive: true);
    });
    final url = (await server.start('127.0.0.1', port, 1, directory.path,
        deviceId: 'desktop'))!;
    final result = await TextDelivery.send(
      envelope: envelope, lanUrls: [url],
      sendToServer: (_) async => fail('The real LAN receiver is available'),
    );
    expect(result, TextDeliveryChannel.lan);
    expect(await received.future.timeout(const Duration(seconds: 3)), {
      'text': (envelope['payload'] as Map)['text'], 'from': 'phone', 'id': 'one', 'ts': 123,
    });
    await TextDelivery.send(
      envelope: {...envelope, 'toDeviceId': 'wrong-device'}, lanUrls: [url],
      sendToServer: (_) async {},
    );
    expect(arrivals, 1);
  });

  test('guest text succeeds over LAN without ever contacting server', () async {
    final result = await TextDelivery.send(
      envelope: envelope,
      lanUrls: ['http://192.0.2.1:9080'],
      client: MockClient((request) async {
        expect(request.url.path, '/message');
        final body = jsonDecode(utf8.decode(request.bodyBytes)) as Map;
        expect(body['text'], (envelope['payload'] as Map)['text']);
        expect(body['textId'], 'one');
        expect(body['toDeviceId'], 'desktop');
        return http.Response('', 200);
      }),
      sendToServer: (_) async => fail('Offline LAN must not need a server'),
    );
    expect(result, TextDeliveryChannel.lan);
  });

  test(
    'stale remembered address falls back with the same text identity',
    () async {
      var serverCalls = 0;
      var lanCalls = 0;
      final result = await TextDelivery.send(
        envelope: envelope,
        lanUrls: ['http://192.0.2.1:9080', 'http://192.0.2.1:9080'],
        client: MockClient((_) async {
          lanCalls++;
          return http.Response('', 403);
        }),
        sendToServer: (message) async {
          serverCalls++;
          expect(message, same(envelope));
        },
      );
      expect(result, TextDeliveryChannel.server);
      expect(lanCalls, 1);
      expect(serverCalls, 1);
    },
  );

  test('LAN timeout does not leave text permanently sending', () async {
    final pending = Completer<http.Response>();
    final result = await TextDelivery.send(
      envelope: envelope,
      lanUrls: ['http://192.0.2.1:9080'],
      client: MockClient((_) => pending.future),
      lanTimeout: const Duration(milliseconds: 10),
      sendToServer: (_) async {},
    );
    expect(result, TextDeliveryChannel.server);
    pending.complete(http.Response('', 200));
  });

  test(
    'unreachable LAN tries another known address before the server',
    () async {
      final result = await TextDelivery.send(
        envelope: envelope,
        lanUrls: ['http://192.0.2.1:9080', 'http://192.0.2.2:9080'],
        client: MockClient((request) async {
          if (request.url.host == '192.0.2.1')
            throw http.ClientException('offline');
          return http.Response('', 200);
        }),
        sendToServer: (_) async => fail('Second LAN address is reachable'),
      );
      expect(result, TextDeliveryChannel.lan);
    },
  );

  test(
    'no LAN address uses signaling; server failure remains a failure',
    () async {
      await expectLater(
        TextDelivery.send(
          envelope: envelope,
          lanUrls: [],
          sendToServer: (_) async => throw StateError('unavailable'),
        ),
        throwsStateError,
      );
    },
  );

  test('server timeout remains a failure', () async {
    final pending = Completer<void>();
    await expectLater(
      TextDelivery.send(
        envelope: envelope,
        lanUrls: [],
        sendToServer: (_) => pending.future,
        serverTimeout: const Duration(milliseconds: 10),
      ),
      throwsA(isA<TimeoutException>()),
    );
    pending.complete();
  });

  test('LAN, retry and server history share one incoming text identity', () {
    final first = MessageEnvelope.fromJson(envelope);
    final replay = MessageEnvelope.fromJson({...envelope, 'ts': 456});
    final otherSender = MessageEnvelope.fromJson({
      ...envelope,
      'fromDeviceId': 'other',
    });
    expect(envelopeToMessage(first).id, envelopeToMessage(replay).id);
    expect(
      envelopeToMessage(first).id,
      isNot(envelopeToMessage(otherSender).id),
    );
    final legacy = MessageEnvelope.fromJson({
      ...envelope,
      'payload': {'text': 'old', 'localId': 'legacy'},
    });
    expect(envelopeToMessage(legacy).id, '123_phone');
  });
}
