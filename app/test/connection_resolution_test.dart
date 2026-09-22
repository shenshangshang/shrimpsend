import 'package:flutter_test/flutter_test.dart';
import 'package:app/api/devices.dart';
import 'package:app/network/connection_resolution.dart';
import 'package:app/network/link_models.dart';
import 'package:app/providers/device_provider.dart';

void main() {
  group('resolveSendModeAutoPreferHttp', () {
    List<ConnectionCandidate> candidates({
      bool lan = false,
      bool webrtc = false,
      bool s3 = false,
    }) {
      return [
        ConnectionCandidate(
          mode: SendMode.lan,
          kind: SmartLinkKind.sameLan,
          available: lan,
          attemptable: true,
          reason: '',
        ),
        ConnectionCandidate(
          mode: SendMode.webrtc,
          kind: SmartLinkKind.sameLan,
          available: webrtc,
          attemptable: true,
          reason: '',
        ),
        ConnectionCandidate(
          mode: SendMode.s3,
          kind: SmartLinkKind.internetRelay,
          available: s3,
          attemptable: true,
          reason: '',
        ),
      ];
    }

    test('prefers lan when all available', () {
      expect(
        resolveSendModeAutoPreferHttp(
          candidates: candidates(lan: true, webrtc: true, s3: true),
          isLoggedIn: true,
          isRegisteredPeer: true,
        ),
        SendMode.lan,
      );
    });

    test('legacy auto-prefer still skips webrtc for session bar helpers', () {
      expect(
        resolveSendModeAutoPreferHttp(
          candidates: candidates(webrtc: true, s3: true),
          isLoggedIn: true,
          isRegisteredPeer: true,
        ),
        SendMode.s3,
      );
    });

    test('falls back to s3 when only s3 available', () {
      expect(
        resolveSendModeAutoPreferHttp(
          candidates: candidates(s3: true),
          isLoggedIn: true,
          isRegisteredPeer: true,
        ),
        SendMode.s3,
      );
    });

    test('upgrades from s3 to lan when http comes online', () {
      final onlyS3 = resolveSendModeAutoPreferHttp(
        candidates: candidates(s3: true),
        isLoggedIn: true,
        isRegisteredPeer: true,
      );
      expect(onlyS3, SendMode.s3);

      final withHttp = resolveSendModeAutoPreferHttp(
        candidates: candidates(lan: true, s3: true),
        isLoggedIn: true,
        isRegisteredPeer: true,
      );
      expect(withHttp, SendMode.lan);
    });
  });

  group('visibleConnectionCandidatesForUi', () {
    List<ConnectionCandidate> allModes() => [
      ConnectionCandidate(
        mode: SendMode.lan,
        kind: SmartLinkKind.sameLan,
        available: false,
        attemptable: true,
        reason: '',
      ),
      ConnectionCandidate(
        mode: SendMode.webrtc,
        kind: SmartLinkKind.sameLan,
        available: false,
        attemptable: true,
        reason: '',
      ),
      ConnectionCandidate(
        mode: SendMode.nearby,
        kind: SmartLinkKind.sameLan,
        available: true,
        attemptable: true,
        reason: '',
      ),
      ConnectionCandidate(
        mode: SendMode.s3,
        kind: SmartLinkKind.internetRelay,
        available: true,
        attemptable: true,
        reason: '',
      ),
    ];

    test('guest keeps nearby and webrtc, hides S3', () {
      final visible = visibleConnectionCandidatesForUi(
        candidates: allModes(),
        isLoggedIn: false,
        isRegisteredPeer: false,
      );
      expect(visible.map((c) => c.mode).toSet(), {
        SendMode.nearby,
        SendMode.webrtc,
      });
    });

    test('logged-in external peer keeps nearby and HTTP', () {
      final visible = visibleConnectionCandidatesForUi(
        candidates: allModes(),
        isLoggedIn: true,
        isRegisteredPeer: false,
      );
      expect(visible.map((c) => c.mode).toSet(), {
        SendMode.nearby,
        SendMode.lan,
      });
    });
  });

  group('buildConnectionCandidates guest webrtc', () {
    test('unsigned-in paired peer can attempt WebRTC', () {
      final context = SelectedConnectionContext(
        selectedDeviceId: 'peer-1',
        localOs: 'ios',
        peer: DeviceDto(deviceId: 'peer-1', name: 'Peer'),
        chain: const [SmartLinkKind.sameLan, SmartLinkKind.internetRelay],
        reach: DeviceReachDetail.offlineDetail,
        s3Configured: false,
        s3Online: false,
        isLoggedIn: false,
        isRegisteredPeer: false,
      );
      final webrtc = buildConnectionCandidates(
        context: context,
      ).firstWhere((c) => c.mode == SendMode.webrtc);
      expect(webrtc.attemptable, isTrue);
      expect(webrtc.available, isFalse);
    });
  });
}
