import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app/api/devices.dart';
import 'package:app/l10n/generated/app_localizations.dart';
import 'package:app/lan/transfer_worker.dart';
import 'package:app/main.dart' as app;
import 'package:app/providers/device_provider.dart';
import 'package:app/providers/realtime_hub_provider.dart';
import 'package:app/ui/product_workspace.dart';
import 'package:app/widgets/app_confirm_dialog.dart';
import 'package:app/widgets/chat/chat_header.dart';
import 'package:app/widgets/devices/device_conversation_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('remove a confirmed stale pairing through the Mac device menu', (
    tester,
  ) async {
    const staleId = String.fromEnvironment('STALE_DEVICE_ID');
    const phoneUrl = String.fromEnvironment('CURRENT_PHONE_URL');
    const output = String.fromEnvironment('DEVICE_CLEANUP_RESULT');
    expect(
      staleId,
      isNotEmpty,
      reason: 'Cleanup requires an explicit obsolete test identity',
    );
    expect(phoneUrl, isNotEmpty);
    app.main([]);
    await binding.setSurfaceSize(const Size(1280, 900));
    Future<void> waitFor(FutureOr<bool> Function() ready) async {
      final end = DateTime.now().add(const Duration(seconds: 60));
      while (DateTime.now().isBefore(end)) {
        if (await ready()) return;
        await tester.pump(const Duration(milliseconds: 150));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(await ready(), isTrue);
    }

    await waitFor(() => find.byType(ProductWorkspace).evaluate().isNotEmpty);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ProductWorkspace)),
    );
    await waitFor(() => container.read(realtimeHubProvider).isConnected);
    final phone =
        jsonDecode((await http.get(Uri.parse('$phoneUrl/device-info'))).body)
            as Map;
    final currentId = phone['deviceId'] as String;
    expect(staleId, isNot(currentId));
    expect(await probeHttp(phoneUrl, expectedDeviceId: staleId), isFalse);
    expect(await probeHttp(phoneUrl, expectedDeviceId: currentId), isTrue);
    final roster = container.read(cloudDeviceRosterProvider.notifier);
    await roster.refreshSnapshot();
    final before = container.read(cloudDeviceRosterProvider).value!;
    final stale = before.singleWhere((d) => d.deviceId == staleId);
    expect(stale.platform, 'android');
    expect(stale.name, phone['name']);
    expect(stale.presenceStatus, 'offline');
    expect(before.any((d) => d.deviceId == currentId), isTrue);

    final oldRow = find.byWidgetPredicate(
      (widget) =>
          widget is DeviceConversationItem && widget.device.deviceId == staleId,
    );
    await waitFor(() => oldRow.evaluate().isNotEmpty);
    await tester.tap(oldRow);
    await tester.pump(const Duration(milliseconds: 300));
    final header = find.byType(ChatHeader);
    await tester.tap(
      find.descendant(of: header, matching: find.byIcon(LucideIcons.ellipsis)),
    );
    await tester.pump(const Duration(milliseconds: 300));
    final l10n = AppLocalizations.of(tester.element(header));
    await tester.tap(
      find.widgetWithText(ListTile, l10n.chatScreenTileRemovePeer),
    );
    await waitFor(() => find.byType(AppConfirmDialog).evaluate().isNotEmpty);
    await tester.tap(
      find.descendant(
        of: find.byType(AppConfirmDialog),
        matching: find.byType(FilledButton),
      ),
    );
    await waitFor(
      () => !container
          .read(cloudDeviceRosterProvider)
          .value!
          .any((d) => d.deviceId == staleId),
    );
    await roster.refreshSnapshot();
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      (await listPairedDevices()).any((d) => d.deviceId == staleId),
      isFalse,
    );
    expect(
      container.read(pairedPeersProvider).any((d) => d.deviceId == staleId),
      isFalse,
    );
    expect(oldRow, findsNothing);
    final currentRow = find.byWidgetPredicate(
      (widget) =>
          widget is DeviceConversationItem &&
          widget.device.deviceId == currentId,
    );
    expect(currentRow, findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is DeviceConversationItem &&
            widget.device.name == phone['name'],
      ),
      findsOneWidget,
    );
    await tester.tap(currentRow);
    await tester.pump(const Duration(milliseconds: 300));
    expect(container.read(selectedDeviceIdProvider), currentId);
    expect(tester.takeException(), isNull);
    final result = {
      'removedDeviceId': staleId,
      'retainedDeviceId': currentId,
      'matchingPhoneRows': 1,
      'serverPairRemoved': true,
      'oldIdentityProbeRejected': true,
    };
    if (output.isNotEmpty) await File(output).writeAsString(jsonEncode(result));
    // ignore: avoid_print
    print('DEVICE_CLEANUP_RESULT ${jsonEncode(result)}');
  });
}
