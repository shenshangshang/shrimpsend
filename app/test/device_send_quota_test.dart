import 'package:app/api/device_send_quota.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseDeviceSendQuota reads header json', () {
    const header =
        '{"kind":"signaling","message":{"used":3,"limit":90,"remaining":87,"retryAfterMs":0},"signaling":{"used":600,"limit":600,"remaining":0,"retryAfterMs":12000},"error":"rate_limited"}';
    final quota = parseDeviceSendQuota(
      headers: {'x-device-send-quota': header},
      limited: true,
    );
    expect(quota, isNotNull);
    expect(quota!.kind, 'signaling');
    expect(quota.limited, isTrue);
    expect(quota.signaling.used, 600);
    expect(quota.signaling.remaining, 0);
    expect(quota.message.remaining, 87);
    expect(quota.retryAfterSeconds, 12);
  });

  test('parseDeviceSendQuota reads 429 body', () {
    final quota = parseDeviceSendQuota(
      body:
          '{"error":"rate_limited","kind":"message","message":{"used":90,"limit":90,"remaining":0,"retryAfterMs":4000},"signaling":{"used":1,"limit":600,"remaining":599,"retryAfterMs":0}}',
      limited: true,
    );
    expect(quota!.kind, 'message');
    expect(quota.message.exhausted, isTrue);
    expect(quota.retryAfterSeconds, 4);
  });
}
