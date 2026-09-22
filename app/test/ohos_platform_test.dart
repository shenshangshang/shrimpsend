import 'package:app/network/link_capability.dart';
import 'package:app/network/link_models.dart';
import 'package:app/network/link_strategy.dart';
import 'package:app/utils/runtime_platform.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizeOs maps ohos aliases to harmonyos', () {
    expect(normalizeOs('ohos'), 'harmonyos');
    expect(normalizeOs('HarmonyOS'), 'harmonyos');
    expect(normalizeOs('harmony'), 'harmonyos');
    expect(normalizeOs('android'), 'android');
    expect(normalizeOs(null), 'unknown');
  });

  test('harmonyos peers use the same LAN then relay chain as android', () {
    expect(
      resolveStrategyChain(localOs: 'harmonyos', peerPlatform: 'android'),
      [SmartLinkKind.sameLan, SmartLinkKind.internetRelay],
    );
    expect(
      resolveStrategyChain(localOs: 'ohos', peerPlatform: 'ios'),
      [SmartLinkKind.sameLan, SmartLinkKind.internetRelay],
    );
    expect(
      resolveStrategyChain(localOs: 'harmonyos', peerPlatform: 'windows'),
      [
        SmartLinkKind.sameLan,
        SmartLinkKind.pcHotspot,
        SmartLinkKind.internetRelay,
      ],
    );
  });

  test('OhosCapabilities stay enabled on non-ohos hosts', () {
    expect(RuntimePlatform.isOhos, isFalse);
    expect(OhosCapabilities.lanMdns, isTrue);
    expect(OhosCapabilities.webrtc, isTrue);
    expect(OhosCapabilities.s3Cloud, isTrue);
    expect(OhosCapabilities.lanHttp, isTrue);
  });

  test('osName is never unknown on this host', () {
    expect(RuntimePlatform.osName, isNot(equals('unknown')));
    expect(RuntimePlatform.platformTag, isNot(equals('unknown')));
  });
}
