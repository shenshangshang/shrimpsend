import 'package:app/api/mailbox.dart';
import 'package:app/config/env.dart';
import 'package:app/services/realtime_hub.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Env websocketEndpointFromHttpApi', () {
    test('maps https API host to same-origin wss', () {
      expect(
        Env.websocketEndpointFromHttpApi('https://api.xiachuan.net'),
        'wss://api.xiachuan.net/wkws',
      );
    });

    test('maps http API with port to ws on that port', () {
      expect(
        Env.websocketEndpointFromHttpApi('http://192.168.0.104:9000'),
        'ws://192.168.0.104:9000/wkws',
      );
    });

    test('http_stream stays on https', () {
      expect(
        Env.httpStreamEndpointFromHttpApi('https://api.xiachuan.net'),
        'https://api.xiachuan.net/wkws',
      );
    });
  });

  group('MailboxPendingItem', () {
    test('parses id and envelope map', () {
      final item = MailboxPendingItem.fromJson({
        'id': 12,
        'data': {'type': 'lan_file_offer', 'fromDeviceId': 'phone'},
      });
      expect(item.id, 12);
      expect(item.data['type'], 'lan_file_offer');
    });
  });

  group('RealtimeHub mailbox ingest', () {
    test('dispatches envelopes and advances afterId', () async {
      final hub = RealtimeHub(
        tokenFetcher: ({required deviceId, required platform}) async =>
            throw StateError('unused'),
        mailboxFetcher: ({required deviceId, afterId = 0}) async => [],
      );
      final received = <Map<String, dynamic>>[];
      final sub = hub.listenPublications(received.add);

      await hub.ingestMailbox([
        MailboxPendingItem(
          id: 7,
          data: {'type': 'webrtc_offer', 'fromDeviceId': 'a'},
        ),
        MailboxPendingItem(
          id: 9,
          data: {'type': 'lan_file_offer', 'fromDeviceId': 'b'},
        ),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(2));
      expect(received[0]['type'], 'webrtc_offer');
      expect(received[1]['type'], 'lan_file_offer');

      final replayed = <Map<String, dynamic>>[];
      final late = hub.listenPublications(replayed.add);
      expect(replayed, hasLength(2));
      await late.cancel();

      await sub.cancel();
      await hub.dispose();
    });
  });
}
