import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:app/main.dart' as app;
import 'package:app/api/client.dart';
import 'package:app/api/devices.dart';
import 'package:app/device_id.dart';
import 'package:app/providers/device_provider.dart';
import 'package:app/providers/realtime_hub_provider.dart';
import 'package:app/ui/product_workspace.dart';
import 'package:app/webrtc/webrtc_manager.dart';
import 'package:app/webrtc/signaling_channel.dart';
import 'package:app/widgets/chat/chat_composer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native client sends text and WebRTC file to Android', (
    tester,
  ) async {
    app.main([]);
    Future<void> waitFor(bool Function() ready) async {
      final end = DateTime.now().add(const Duration(seconds: 60));
      while (!ready() && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 200));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(ready(), isTrue);
    }

    await waitFor(() => find.byType(ProductWorkspace).evaluate().isNotEmpty);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ProductWorkspace)),
    );
    await waitFor(() => container.read(realtimeHubProvider).isConnected);
    const url = String.fromEnvironment('NATIVE_QA_PEER_URL');
    expect(url, isNotEmpty);
    final info =
        jsonDecode((await http.get(Uri.parse('$url/device-info'))).body) as Map;
    final peerId = info['deviceId'] as String;
    final response = await http.post(
      Uri.parse('$apiBaseUrl/api/devices/pair'),
      headers: deviceApiHeaders,
      body: jsonEncode({'peerDeviceId': peerId}),
    );
    expect(response.statusCode, 204);
    container
        .read(pairedPeersProvider.notifier)
        .upsert(
          DeviceDto(
            deviceId: peerId,
            name: info['name'] as String,
            platform: info['platform'] as String,
            lanHttpUrl: url,
          ),
        );
    await container.read(cloudDeviceRosterProvider.notifier).refreshSnapshot();
    container.read(selectedDeviceIdProvider.notifier).select(peerId);
    await waitFor(() => find.byType(ChatComposer).evaluate().isNotEmpty);
    final runId = DateTime.now().millisecondsSinceEpoch.toString();
    final composer = find.byType(ChatComposer);
    await tester.enterText(
      find.descendant(of: composer, matching: find.byType(TextField)),
      'MAC-ANDROID-QA-$runId 文本互传',
    );
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(
      find.descendant(of: composer, matching: find.byType(FilledButton)).last,
    );
    await tester.pump(const Duration(seconds: 1));
    final me = await getOrCreateDeviceId();
    final rtc = WebRTCManager();
    var sent = false;
    String? failure;
    rtc.onFileSent = (_, __) => sent = true;
    rtc.onFileFailed = (_, __, error) => failure = error;
    final subscription = container
        .read(realtimeHubProvider)
        .publications
        .listen((envelope) {
          if ([
                'webrtc_answer',
                'webrtc_ice_candidate',
              ].contains(envelope['type']) &&
              envelope['payload'] is Map) {
            rtc.handleSignal(
              Map<String, dynamic>.from(envelope['payload'] as Map),
              me,
            );
          }
        });
    final directory = await Directory.systemTemp.createTemp(
      'shrimpsend-android-qa-',
    );
    try {
      final file = File('${directory.path}/mac-android-qa-$runId.bin');
      await file.writeAsBytes(
        List<int>.generate(5 * 1024 * 1024, (i) => i % 239),
      );
      await rtc.initiateTransfer(
        targetDeviceId: peerId,
        localDeviceId: me,
        files: [
          (
            filePath: file.path,
            meta: WebRTCFileMeta(
              fileId: 'mac-android-$runId',
              fileName: file.uri.pathSegments.last,
              fileSize: await file.length(),
              mimeType: 'application/octet-stream',
              senderLocalId: 'mac-android-$runId',
            ),
          ),
        ],
      );
      await waitFor(() => sent || failure != null);
      expect(failure, isNull);
      expect(sent, isTrue);
      // This receipt is generated only after the phone's file_ack.
      print(
        'NATIVE_TRANSFER_RESULT ${jsonEncode({'fileName': file.uri.pathSegments.last, 'bytes': await file.length(), 'receiverAck': sent, 'runId': runId})}',
      );
    } finally {
      await subscription.cancel();
      rtc.closeAll();
      await directory.delete(recursive: true);
    }
    expect(tester.takeException(), isNull);
  });
}
