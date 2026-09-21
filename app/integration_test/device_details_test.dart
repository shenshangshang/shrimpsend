import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:app/main.dart' as app;
import 'package:app/device_id.dart';
import 'package:app/api/device_identity.dart';
import 'package:app/api/client.dart' show apiBaseUrl;
import 'package:app/providers/realtime_hub_provider.dart';
import 'package:app/lan/lan_discovery.dart';
import 'package:app/ui/product_workspace.dart';
import 'package:app/ui/product_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:uuid/uuid.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real macOS rename updates LAN and guest peers while sidebar and background service survive',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      app.main([]);
      Future<void> waitUntil(
        bool Function() condition, {
        int seconds = 30,
      }) async {
        final end = DateTime.now().add(Duration(seconds: seconds));
        while (!condition() && DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(condition(), isTrue);
      }

      await waitUntil(
        () => find.byType(ProductWorkspace).evaluate().isNotEmpty,
        seconds: 60,
      );
      final workspace = tester.state<ProductWorkspaceState>(
        find.byType(ProductWorkspace),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(ProductWorkspace)),
      );
      await waitUntil(() => container.read(realtimeHubProvider).isConnected);
      final me = await getOrCreateDeviceId();
      final output = Directory(const String.fromEnvironment('DEVICE_QA_OUTPUT', defaultValue: '/tmp/shrimpsend-device-qa'));
      await output.create(recursive: true);
      final originalFile = File('${output.path}/device-detail-original-name.txt');
      final original = await originalFile.exists() ? await originalFile.readAsString() : await getDeviceName();
      if (!await originalFile.exists()) await originalFile.writeAsString(original);
      final observerId = 'native-presence-qa-${const Uuid().v4()}';
      final session = await http.post(
        Uri.parse('$apiBaseUrl/api/realtime/device-session'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'deviceId': observerId,
          'deviceSecret': const Uuid().v4(),
          'platform': 'web',
        }),
      );
      expect(session.statusCode, 200);
      final token =
          (jsonDecode(session.body) as Map)['deviceAccessToken'] as String;
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };
      final pairing = await http.post(
        Uri.parse('$apiBaseUrl/api/devices/pair'),
        headers: headers,
        body: jsonEncode({'peerDeviceId': me}),
      );
      expect(pairing.statusCode, 204);
      Future<Map> peer() async {
        final response = await http.get(
          Uri.parse('$apiBaseUrl/api/devices/paired'),
          headers: headers,
        );
        expect(response.statusCode, 200);
        return (jsonDecode(response.body) as List).single as Map;
      }

      String? lanUrl;
      try {
        for (var i = 0; i < 50; i++) {
          final d = await peer();
          if (d['presenceStatus'] == 'online' && d['lanHttpUrl'] != null) {
            lanUrl = d['lanHttpUrl'] as String;
            break;
          }
          await tester.pump(const Duration(milliseconds: 400));
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        expect(lanUrl, isNotNull);
        await binding.setSurfaceSize(const Size(1280, 900));
        await tester.pump(const Duration(milliseconds: 300));
        final navigation = find.byType(ProductNavigation, skipOffstage: false);
        final rail = tester.element(navigation);
        final railRect = tester.getRect(navigation);
        unawaited(workspace.openRoute('/settings'));
        await waitUntil(() => find.text('修改').evaluate().isNotEmpty);
        await tester.tap(find.text('修改').first);
        await tester.pump(const Duration(milliseconds: 300));
        final renamed = 'Mac 细节验证 ${DateTime.now().second}';
        await tester.enterText(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextField),
          ),
          renamed,
        );
        await tester.pump(const Duration(milliseconds: 100));
        final started = DateTime.now();
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('保存'),
          ),
        );
        await tester.pump(const Duration(milliseconds: 400));
        await waitUntil(() => find.byType(AlertDialog).evaluate().isEmpty);
        expect(await getDeviceName(), renamed);
        for (var i = 0; i < 30 && (await peer())['name'] != renamed; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect((await peer())['name'], renamed);
        final elapsed = DateTime.now().difference(started).inMilliseconds;
        final info = await http.get(Uri.parse('$lanUrl/device-info'));
        expect((jsonDecode(info.body) as Map)['name'], renamed);
        expect(LanDiscoveryService.instance!.deviceName, renamed);
        expect(tester.element(navigation), same(rail));
        expect(tester.getRect(navigation), railRect);
        final before = (await peer())['lastSeen'] as int;
        binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        await Future<void>.delayed(const Duration(seconds: 17));
        await tester.pump();
        final background = await peer();
        expect(background['presenceStatus'], 'online');
        expect(background['lastSeen'] as int, greaterThan(before));
        binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        final result = {
          'renameSyncMs': elapsed,
          'lanIdentityUpdated': true,
          'sidebarRetained': true,
          'backgroundHeartbeat': true,
        };
        await File(
          '${output.path}/device-detail-native-result.json',
        ).writeAsString(jsonEncode(result));
        expect(tester.takeException(), isNull);
      } finally {
        binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await setDeviceName(original);
        await syncDeviceName();
        await originalFile.delete();
        await tester.pump(const Duration(milliseconds: 300));
        await http.delete(
          Uri.parse(
            '$apiBaseUrl/api/devices/paired/${Uri.encodeComponent(me)}',
          ),
          headers: headers,
        );
      }
    },
  );
}
