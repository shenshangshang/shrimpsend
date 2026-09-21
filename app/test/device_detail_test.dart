import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:app/api/devices.dart';
import 'package:app/device_id.dart';
import 'package:app/lan/transfer_worker.dart';
import 'package:app/providers/device_provider.dart';
import 'package:app/providers/device_alias_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'late snapshots cannot undo a realtime rename and cleared roster stays cleared',
    () async {
      final requests = <Completer<List<DeviceDto>>>[];
      final container = ProviderContainer(
        overrides: [
          cloudDeviceRosterProvider.overrideWith(
            (ref) => CloudDeviceRosterNotifier(
              ref,
              fetchDevices: () {
                final c = Completer<List<DeviceDto>>();
                requests.add(c);
                return c.future;
              },
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      final roster = container.read(cloudDeviceRosterProvider.notifier);
      roster.replaceSnapshot([
        DeviceDto(deviceId: 'a', name: 'Old', presenceUpdatedAt: 1),
      ]);
      final pending = roster.refreshSnapshot();
      roster.applyUpsert(
        DeviceDto(deviceId: 'a', name: 'New', presenceUpdatedAt: 3),
      );
      requests[0].complete([
        DeviceDto(deviceId: 'a', name: 'Old', presenceUpdatedAt: 2),
      ]);
      await pending;
      expect(
        container.read(cloudDeviceRosterProvider).value!.single.name,
        'New',
      );
      final next = roster.refreshSnapshot();
      roster.clear();
      requests[1].complete([DeviceDto(deviceId: 'a', name: 'Old')]);
      await next;
      expect(container.read(cloudDeviceRosterProvider).value, isEmpty);
    },
  );
  test(
    'saved peers are not assumed online, explicit nicknames persist and can be cleared',
    () async {
      SharedPreferences.setMockInitialValues({
        'ultrasend_paired_peers': '[{"deviceId":"a","name":"Stored"}]',
      });
      final peers = PairedPeersNotifier();
      addTearDown(peers.dispose);
      await Future<void>.delayed(Duration.zero);
      expect(peers.state.single.presenceStatus, isNull);
      final names = DeviceAliases();
      addTearDown(names.dispose);
      await names.rename('a', 'Work Mac');
      final reloaded = DeviceAliases();
      addTearDown(reloaded.dispose);
      await Future<void>.delayed(Duration.zero);
      expect(reloaded.state['a'], 'Work Mac');
      await reloaded.rename('a', '  ');
      expect(reloaded.state, isEmpty);
    },
  );
  test(
    'local rename is trimmed, queued offline and emits one change; invalid input is rejected',
    () async {
      final changed = deviceNameChanges.stream.first;
      await setDeviceName('  工作 Mac  ');
      expect(await changed, '工作 Mac');
      expect(await getDeviceName(), '工作 Mac');
      expect(
        (await SharedPreferences.getInstance()).getString(pendingDeviceNameKey),
        '工作 Mac',
      );
      await expectLater(setDeviceName(' \n '), throwsArgumentError);
      await expectLater(setDeviceName('bad\nname'), throwsArgumentError);
      expect(await getDeviceName(), '工作 Mac');
    },
  );
  test('background reach checks keep a proven connection visibly online', () {
    expect(
      const DeviceReachDetail(directHttp: true, checking: true).uiReachStatus,
      DeviceReachStatus.online,
    );
    expect(
      const DeviceReachDetail(pullReachable: true, checking: true).status,
      'pull_online',
    );
    expect(const DeviceReachDetail(checking: true).status, 'checking');
  });
  test(
    'renaming the HTTP receiver updates all workers without restarting its listener',
    () async {
      final dir = await Directory.systemTemp.createTemp('device-name-test-');
      addTearDown(() => dir.delete(recursive: true));
      final portFinder = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = portFinder.port;
      await portFinder.close();
      final server = HttpTransferServer(
        onFileReceived:
            (_, __, ___, {messageId, senderLocalId, lastModifiedMs}) {},
      );
      addTearDown(server.stop);
      await server.start(
        '127.0.0.1',
        port,
        2,
        dir.path,
        deviceId: 'mac-test',
        deviceName: 'Old Mac',
        platform: 'macos',
      );
      server.updateDeviceName('新 Mac');
      final client = HttpOverrides.runWithHttpOverrides(
        () => HttpClient(),
        _RealHttpOverrides(),
      );
      addTearDown(() => client.close(force: true));
      for (var i = 0; i < 6; i++) {
        final response = await (await client.getUrl(
          Uri.parse('http://127.0.0.1:$port/device-info'),
        )).close();
        final body =
            jsonDecode(await utf8.decoder.bind(response).join()) as Map;
        expect(response.statusCode, 200);
        expect(body['name'], '新 Mac');
        expect(body['deviceId'], 'mac-test');
      }
    },
  );
}

class _RealHttpOverrides extends HttpOverrides {}
