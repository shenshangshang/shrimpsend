import 'dart:convert';

import 'package:app/services/wukongim_jsonrpc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('unwraps type 200 envelope from base64 payload', () {
    final wrapped = jsonEncode({
      'type': 200,
      'v': 1,
      'envelope': {'type': 'text', 'fromDeviceId': 'a'},
    });
    final params = {
      'payload': base64Encode(utf8.encode(wrapped)),
    };
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
