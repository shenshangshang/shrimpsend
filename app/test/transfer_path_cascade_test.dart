import 'package:flutter_test/flutter_test.dart';
import 'package:app/network/transfer_path_cascade.dart';

void main() {
  TransferPathInput input({
    bool localIsWeb = false,
    bool peerIsWeb = false,
    bool isLoggedIn = true,
    bool webrtcAvailable = true,
    bool s3Configured = true,
    bool s3Online = true,
    bool isS3VirtualSession = false,
  }) {
    return TransferPathInput(
      localIsWeb: localIsWeb,
      peerIsWeb: peerIsWeb,
      isLoggedIn: isLoggedIn,
      webrtcAvailable: webrtcAvailable,
      s3Configured: s3Configured,
      s3Online: s3Online,
      isS3VirtualSession: isS3VirtualSession,
    );
  }

  group('applicableTransferHops', () {
    test('App → App includes push, pull, webrtc, s3', () {
      expect(applicableTransferHops(input()), [
        TransferHop.httpPush,
        TransferHop.httpPull,
        TransferHop.webrtc,
        TransferHop.s3,
      ]);
    });

    test('Web → App is push then webrtc then s3, no pull', () {
      expect(
        applicableTransferHops(input(localIsWeb: true, peerIsWeb: false)),
        [TransferHop.httpPush, TransferHop.webrtc, TransferHop.s3],
      );
    });

    test('App → Web is pull then webrtc then s3, no push', () {
      expect(
        applicableTransferHops(input(localIsWeb: false, peerIsWeb: true)),
        [TransferHop.httpPull, TransferHop.webrtc, TransferHop.s3],
      );
    });

    test('Web → Web skips HTTP', () {
      expect(
        applicableTransferHops(input(localIsWeb: true, peerIsWeb: true)),
        [TransferHop.webrtc, TransferHop.s3],
      );
    });

    test('guest keeps HTTP direction and webrtc, omits S3', () {
      expect(
        applicableTransferHops(
          input(localIsWeb: true, peerIsWeb: false, isLoggedIn: false),
        ),
        [TransferHop.httpPush, TransferHop.webrtc],
      );
      expect(
        applicableTransferHops(
          input(localIsWeb: false, peerIsWeb: true, isLoggedIn: false),
        ),
        [TransferHop.httpPull, TransferHop.webrtc],
      );
    });

    test('S3 virtual session is S3 only when online', () {
      expect(
        applicableTransferHops(input(isS3VirtualSession: true)),
        [TransferHop.s3],
      );
      expect(
        applicableTransferHops(
          input(isS3VirtualSession: true, s3Online: false),
        ),
        isEmpty,
      );
      expect(
        applicableTransferHops(
          input(isS3VirtualSession: true, isLoggedIn: false),
        ),
        isEmpty,
      );
    });

    test('omits webrtc when unavailable', () {
      expect(
        applicableTransferHops(input(webrtcAvailable: false)),
        [TransferHop.httpPush, TransferHop.httpPull, TransferHop.s3],
      );
    });
  });

  group('TransferPhase', () {
    test('connecting phases are indeterminate', () {
      expect(TransferPhase.isConnecting(TransferPhase.tryingHttp), isTrue);
      expect(TransferPhase.isConnecting(TransferPhase.connectingWebrtcFallback), isTrue);
      expect(TransferPhase.isConnecting(TransferPhase.sendingHttp), isFalse);
      expect(TransferPhase.channelOf(TransferPhase.tryingS3Fallback), 's3');
    });
  });

  group('TransferHopSkipCache', () {
    test('skips a hop that just failed until TTL', () {
      final cache = TransferHopSkipCache(ttl: const Duration(seconds: 30));
      cache.markFailed('peer', TransferHop.httpPush);
      expect(cache.shouldSkip('peer', TransferHop.httpPush), isTrue);
      expect(cache.shouldSkip('peer', TransferHop.webrtc), isFalse);
      expect(
        cache.filter('peer', TransferHop.values),
        isNot(contains(TransferHop.httpPush)),
      );
    });

    test('success clears the skip', () {
      final cache = TransferHopSkipCache();
      cache.markFailed('peer', TransferHop.httpPush);
      cache.markSucceeded('peer', TransferHop.httpPush);
      expect(cache.shouldSkip('peer', TransferHop.httpPush), isFalse);
    });
  });

  group('isLanFileOfferForMe', () {
    test('directed toDeviceId wins over target list', () {
      expect(
        isLanFileOfferForMe(
          me: 'web',
          toDeviceId: 'web',
          targetDeviceIds: ['phone'],
        ),
        isTrue,
      );
      expect(
        isLanFileOfferForMe(
          me: 'web',
          toDeviceId: 'phone',
          targetDeviceIds: ['web'],
        ),
        isFalse,
      );
    });

    test('falls back to targetDeviceIds when toDeviceId is absent', () {
      expect(
        isLanFileOfferForMe(
          me: 'web',
          targetDeviceIds: ['web', 'phone'],
        ),
        isTrue,
      );
      expect(
        isLanFileOfferForMe(me: 'web', targetDeviceIds: ['phone']),
        isFalse,
      );
      expect(isLanFileOfferForMe(me: 'web'), isFalse);
    });
  });
}
