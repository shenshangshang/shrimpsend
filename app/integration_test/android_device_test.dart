import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app/api/client.dart';
import 'package:app/api/devices.dart';
import 'package:app/device_id.dart';
import 'package:app/services/android_receive_storage.dart';
import 'package:app/webrtc/webrtc_manager.dart';
import 'package:app/webrtc/signaling_channel.dart';
import 'package:app/main.dart' as app;
import 'package:app/models/pending_file_entry.dart';
import 'package:app/providers/device_provider.dart';
import 'package:app/providers/pending_files_provider.dart';
import 'package:app/providers/realtime_hub_provider.dart';
import 'package:app/ui/product_scaffold.dart';
import 'package:app/ui/product_workspace.dart';
import 'package:app/widgets/chat/chat_composer.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android real device: pages, text and files to a live Mac', (
    tester,
  ) async {
    app.main([]);
    Future<void> waitFor(bool Function() ready, {int seconds = 45}) async {
      final deadline = DateTime.now().add(Duration(seconds: seconds));
      while (!ready() && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 150));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(ready(), isTrue);
    }

    await waitFor(
      () => find.byType(ProductWorkspace).evaluate().isNotEmpty,
      seconds: 90,
    );
    final output = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/android-qa',
    );
    await output.create(recursive: true);
    Future<void> capture(String name) async {
      await tester.pump(const Duration(milliseconds: 500));
      final view = binding.renderViews.first;
      // Capture only this app's render tree on the attached test device.
      // ignore: invalid_use_of_protected_member
      final layer = view.layer;
      if (layer is OffsetLayer) {
        final image = await layer.toImage(view.paintBounds);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '${output.path}/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      }
    }

    final workspace = tester.state<ProductWorkspaceState>(
      find.byType(ProductWorkspace),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ProductWorkspace)),
    );
    await waitFor(() => container.read(realtimeHubProvider).isConnected);
    await capture('01-devices');
    for (final route in [
      '/files',
      '/files/recent',
      '/files/tasks',
      '/files/cloud',
      '/files/connections',
      '/settings',
      '/settings/receiving',
      '/settings/appearance',
      '/settings/language',
      '/settings/fonts',
      '/authorize',
      '/settings/membership',
      '/settings/help',
      '/account',
    ]) {
      unawaited(workspace.openRoute(route));
      await tester.pump(const Duration(milliseconds: 500));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await capture(route.replaceAll('/', '_'));
      expect(tester.takeException(), isNull, reason: route);
    }
    workspace.selectSection(ProductSection.transfer);
    await tester.pump(const Duration(milliseconds: 300));
    const macUrl = String.fromEnvironment(
      'ANDROID_QA_PEER_URL',
      defaultValue: 'http://192.168.0.100:9080',
    );
    final infoResponse = await http.get(Uri.parse('$macUrl/device-info'));
    expect(infoResponse.statusCode, 200);
    final info = jsonDecode(infoResponse.body) as Map;
    final peerId = info['deviceId'] as String;
    final pairing = await http.post(
      Uri.parse('$apiBaseUrl/api/devices/pair'),
      headers: deviceApiHeaders,
      body: jsonEncode({'peerDeviceId': peerId}),
    );
    expect(pairing.statusCode, 204);
    await container.read(cloudDeviceRosterProvider.notifier).refreshSnapshot();
    container
        .read(pairedPeersProvider.notifier)
        .upsert(
          DeviceDto(
            deviceId: peerId,
            name: info['name'] as String,
            platform: 'macos',
            lanHttpUrl: macUrl,
          ),
        );
    container.read(selectedDeviceIdProvider.notifier).select(peerId);
    await waitFor(() => find.byType(ChatComposer).evaluate().isNotEmpty);
    final runId = DateTime.now().millisecondsSinceEpoch.toString();
    for (final mode in [SendMode.lan]) {
      container.read(chatSendModeAutoProvider.notifier).state = false;
      container
          .read(selectedSendModeProvider.notifier)
          .select(mode, persist: false);
      await tester.pump(const Duration(milliseconds: 500));
      final composer = find.byType(ChatComposer);
      final input = find.descendant(
        of: composer,
        matching: find.byType(TextField),
      );
      await tester.enterText(input, 'ANDROID-QA-$runId-${mode.name} 文本互传');
      await tester.pump(const Duration(milliseconds: 150));
      await tester.tap(
        find.descendant(of: composer, matching: find.byType(FilledButton)).last,
      );
      await tester.pump(const Duration(seconds: 1));
      await Future<void>.delayed(const Duration(seconds: 2));
      await capture('text-${mode.name}');
      final file = File('${output.path}/android-qa-$runId-${mode.name}.bin');
      await file.writeAsBytes(
        List<int>.generate(1024 * 1024, (index) => index % 251),
      );
      await container.read(pendingFilesProvider.notifier).add([
        PendingFileEntry.fromPlatformFile(
          PlatformFile(
            name: file.uri.pathSegments.last,
            size: await file.length(),
            path: file.path,
          ),
        ),
      ]);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(
        find.descendant(of: composer, matching: find.byType(FilledButton)).last,
      );
      await tester.pump(const Duration(seconds: 1));
      await Future<void>.delayed(const Duration(seconds: 8));
      await capture('file-${mode.name}');
      expect(tester.takeException(), isNull);
    }
    final nativeName = 'android-storage-qa-$runId.bin';
    final key = 'storage-qa:$runId';
    final nativePath = await AndroidReceiveStorage.prepare(key, nativeName);
    expect(nativePath, startsWith('/storage/emulated/0/Download/'));
    await File(
      nativePath!,
    ).writeAsBytes(List<int>.generate(4096, (i) => i % 251), flush: true);
    expect(await AndroidReceiveStorage.lookup(key), nativePath);
    final visible = await AndroidReceiveStorage.complete(nativePath, 4096);
    expect(visible, endsWith('/$nativeName'));
    expect(await File(visible!).length(), 4096);
    expect(await AndroidReceiveStorage.complete(nativePath, 4096), visible);
    expect(await AndroidReceiveStorage.lookup(key), isNull);
    final me = await getOrCreateDeviceId();
    final rtc = WebRTCManager();
    var rtcSent = false;
    String? rtcFailure;
    rtc.onFileSent = (_, __) => rtcSent = true;
    rtc.onFileFailed = (_, __, error) => rtcFailure = error;
    final signals = container.read(realtimeHubProvider).publications.listen((
      envelope,
    ) {
      final type = envelope['type'];
      if ((type == 'webrtc_answer' || type == 'webrtc_ice_candidate') &&
          envelope['payload'] is Map) {
        rtc.handleSignal(
          Map<String, dynamic>.from(envelope['payload'] as Map),
          me,
        );
      }
    });
    try {
      final file = File('${output.path}/android-qa-$runId-rtc.bin');
      await file.writeAsBytes(
        List<int>.generate(3 * 1024 * 1024, (i) => i % 251),
      );
      await rtc.initiateTransfer(
        targetDeviceId: peerId,
        localDeviceId: me,
        files: [
          (
            filePath: file.path,
            meta: WebRTCFileMeta(
              fileId: 'android-qa-$runId',
              fileName: file.uri.pathSegments.last,
              fileSize: await file.length(),
              mimeType: 'application/octet-stream',
            ),
          ),
        ],
      );
      await waitFor(() => rtcSent || rtcFailure != null, seconds: 60);
      expect(rtcFailure, isNull);
      expect(rtcSent, isTrue);
    } finally {
      await signals.cancel();
      rtc.closeAll();
    }
    await File('${output.path}/result.json').writeAsString(
      jsonEncode({
        'deviceId': await getOrCreateDeviceId(),
        'peerId': peerId,
        'runId': runId,
        'pages': 14,
      }),
    );
  });
}
