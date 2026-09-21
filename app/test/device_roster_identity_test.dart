import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/api/devices.dart';
import 'package:app/lan/transfer_worker.dart';
import 'package:app/providers/device_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('removing a peer survives an older pending roster response', () async {
    final pending = Completer<List<DeviceDto>>();
    final container = ProviderContainer(
      overrides: [
        cloudDeviceRosterProvider.overrideWith(
          (ref) => CloudDeviceRosterNotifier(
            ref,
            fetchDevices: () => pending.future,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    final roster = container.read(cloudDeviceRosterProvider.notifier);
    final old = DeviceDto(deviceId: 'old-install', name: 'Same phone');
    final current = DeviceDto(deviceId: 'current-install', name: 'Same phone');
    roster.replaceSnapshot([old, current]);
    expect(
      container.read(cloudDeviceRosterProvider).value,
      hasLength(2),
      reason: 'Matching names are not enough to merge independent devices',
    );
    final refresh = roster.refreshSnapshot();
    roster.applyRemove(old.deviceId);
    pending.complete([old, current]);
    await refresh;
    expect(
      container.read(cloudDeviceRosterProvider).value!.single.deviceId,
      current.deviceId,
    );
  });

  test(
    'same IP proves only the current identity, never an old installation',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final paths = <String>[];
      final sub = server.listen((request) async {
        paths.add(request.uri.path);
        if (request.uri.path == '/device-info') {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({'deviceId': 'current-install', 'name': 'Same phone'}),
          );
        }
        await request.response.close();
      });
      addTearDown(sub.cancel);
      final url = 'http://127.0.0.1:${server.port}';
      expect(await _realProbe(url, expectedDeviceId: 'current-install'), isTrue);
      expect(await _realProbe(url, expectedDeviceId: 'old-install'), isFalse);
      expect(paths, [
        '/device-info',
        '/device-info',
      ], reason: 'Each probe still needs only one round trip');
      expect(
        await _realProbe(url),
        isTrue,
        reason: 'Manual discovery can probe before knowing the identity',
      );
    },
  );

  test(
    '200 without matching device info is not proof of online presence',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var attempt = 0;
      final sub = server.listen((request) async {
        request.response.write(attempt++ == 0 ? '{}' : 'not JSON');
        await request.response.close();
      });
      addTearDown(sub.cancel);
      final url = 'http://127.0.0.1:${server.port}';
      expect(await _realProbe(url, expectedDeviceId: 'phone'), isFalse);
      expect(await _realProbe(url, expectedDeviceId: 'phone'), isFalse);
    },
  );

  test('identity response body is covered by the probe timeout', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final sub = server.listen((request) async {
      request.response.write('{');
      await request.response.flush();
      // Deliberately keep the response open until the client's deadline.
    });
    addTearDown(sub.cancel);
    expect(
      await _realProbe(
        'http://127.0.0.1:${server.port}',
        expectedDeviceId: 'phone',
        timeout: const Duration(milliseconds: 80),
      ),
      isFalse,
    );
  });
}

Future<bool> _realProbe(String url, {String? expectedDeviceId, Duration timeout = const Duration(seconds: 5)}) =>
    HttpOverrides.runWithHttpOverrides(
      () => probeHttp(url, expectedDeviceId: expectedDeviceId, timeout: timeout),
      _RealHttpOverrides(),
    );

class _RealHttpOverrides extends HttpOverrides {}
