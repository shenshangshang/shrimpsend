import 'package:app/api/client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  tearDown(() {
    setDeviceAccessToken(null);
    setDeviceSessionRenewal(null);
  });

  test('concurrent expiry and a late 401 share one renewal', () async {
    setDeviceAccessToken('expired');
    var renewals = 0;
    setDeviceSessionRenewal(() async {
      renewals++;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      setDeviceAccessToken('fresh');
    });
    Future<http.Response> run(int delay) => withDeviceAuthRetry(() async {
      final used = deviceApiHeaders['Authorization'];
      if (used == 'Bearer expired') {
        await Future<void>.delayed(Duration(milliseconds: delay));
      }
      return http.Response('', used == 'Bearer fresh' ? 204 : 401);
    });
    final responses = await Future.wait([
      ...List.generate(12, (_) => run(0)),
      run(25),
    ]);
    expect(responses.every((r) => r.statusCode == 204), isTrue);
    expect(renewals, 1);
  });

  test('business errors and delivered messages are never replayed', () async {
    setDeviceSessionRenewal(() async => fail('must not renew'));
    for (final status in [204, 403, 429, 500]) {
      var calls = 0;
      final result = await withDeviceAuthRetry(() async {
        calls++;
        return http.Response('', status);
      });
      expect(result.statusCode, status);
      expect(calls, 1);
    }
  });

  test('network recovery remains possible and retries are bounded', () async {
    setDeviceAccessToken('expired');
    setDeviceSessionRenewal(() async => throw Exception('offline'));
    await expectLater(
      withDeviceAuthRetry(() async => http.Response('', 401)),
      throwsA(isA<Exception>()),
    );
    var calls = 0;
    setDeviceSessionRenewal(() async {});
    final result = await withDeviceAuthRetry(() async {
      calls++;
      return http.Response('', 401);
    });
    expect(result.statusCode, 401);
    expect(calls, 2);
  });
}
