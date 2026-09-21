import 'dart:async';
import 'package:app/ui/product_workspace.dart';
import 'package:app/ui/product_scaffold.dart';
import 'package:app/screens/chat_screen.dart';
import 'package:app/screens/webdav_settings_screen.dart';
import 'dart:io';
import 'dart:convert';
import 'package:app/services/local_webdav_connections.dart';
import 'package:app/services/webdav_session.dart';
import 'dart:ui' as ui;
import 'package:app/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real macOS app renders all product destinations and local settings',
    (tester) async {
      app.main([]);
      for (
        var i = 0;
        i < 120 && find.byType(MaterialApp).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(find.byType(MaterialApp), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      final output = Directory(
        const String.fromEnvironment(
          'PRODUCT_QA_OUTPUT',
          defaultValue: '/tmp/shrimpsend-native-qa',
        ),
      );
      await output.create(recursive: true);
      Future<void> capture(String name) async {
        await tester.pump(const Duration(milliseconds: 500));
        final view = binding.renderViews.first;
        // Rendering the owned app root is intentional in this visual integration test.
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
      final rail = tester.element(find.byType(ProductNavigation));
      final railRect = tester.getRect(find.byType(ProductNavigation));
      final chat = tester.state(find.byType(ChatScreen));
      await capture('01-transfer');
      final routes = <String, String>{
        '02-files': '/files',
        '03-recent': '/files/recent',
        '04-favorites': '/files/favorites',
        '05-tasks': '/files/tasks',
        '06-cloud': '/files/cloud',
        '07-connections': '/files/connections',
        '08-general': '/settings',
        '09-receiving': '/settings/receiving',
        '10-appearance': '/settings/appearance',
        '11-language': '/settings/language',
        '12-fonts': '/settings/fonts',
        '13-shortcuts': '/settings/shortcuts',
        '14-authorization': '/authorize',
        '15-membership': '/settings/membership',
        '16-help': '/settings/help',
        '17-versions': '/settings/version-history',
        '18-logs': '/settings/app-log',
        '19-account': '/account',
        '20-feedback': '/settings/feedback',
      };
      for (final entry in routes.entries) {
        unawaited(workspace.openRoute(entry.value));
        await tester.pump(const Duration(milliseconds: 300));
        // Wait for real network and disk work, not just animation time.
        for (var attempt = 0; attempt < 40; attempt++) {
          await tester.pump(const Duration(milliseconds: 150));
          if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
        await tester.pump(const Duration(milliseconds: 350));
        await capture(entry.key);
        expect(tester.takeException(), isNull, reason: entry.value);
        expect(tester.element(find.byType(ProductNavigation)), same(rail));
        expect(tester.getRect(find.byType(ProductNavigation)), railRect);
        expect(
          tester.state(find.byType(ChatScreen, skipOffstage: false)),
          same(chat),
        );
        workspace.selectSection(ProductSection.transfer);
        await tester.pump(const Duration(milliseconds: 350));
      }
      Future<void> waitFor(Finder target) async {
        for (var i = 0; i < 80 && target.evaluate().isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 200));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(target, findsWidgets);
      }

      unawaited(workspace.openRoute('/files/cloud'));
      await waitFor(find.text('添加 WebDAV'));
      final navigator = Navigator.of(
        tester.element(find.byType(WebDavSettingsScreen)),
      );
      await tester.tap(find.text('添加 WebDAV').first);
      await waitFor(find.byType(TextFormField));
      final name = '本地 QA ${DateTime.now().millisecondsSinceEpoch}';
      await tester.enterText(find.byType(TextFormField).at(0), name);
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'http://127.0.0.1:4318/dav/',
      );
      await capture('21-cloud-connection');
      await tester.ensureVisible(find.widgetWithText(FilledButton, '确定'));
      await tester.tap(find.widgetWithText(FilledButton, '确定'));
      await waitFor(find.widgetWithText(ListTile, name));
      final store = LocalWebDavConnections.instance;
      final connection = (await store.list()).singleWhere(
        (row) => row.name == name,
      );
      try {
        final connectionTile = find.widgetWithText(ListTile, name);
        await tester.ensureVisible(connectionTile);
        await waitFor(connectionTile.hitTestable());
        await tester.tap(connectionTile.hitTestable());
        await waitFor(find.text('快速开始.txt'));
        await capture('22-cloud-files');
        final client = WebDavClient(await store.credentials(connection.id));
        final remotePath = '/native-qa-${connection.id}.txt';
        final bytes = utf8.encode('虾传 Mac 端 WebDAV 实际收发验证');
        final temp = await Directory.systemTemp.createTemp('native-webdav-qa-');
        try {
          await client.uploadFile(remotePath, bytes);
          expect(
            (await client.listDirectory(
              '/',
            )).any((row) => row.name == remotePath.substring(1)),
            isTrue,
          );
          await client.downloadFile(remotePath, '${temp.path}/received.txt');
          expect(await File('${temp.path}/received.txt').readAsBytes(), bytes);
        } finally {
          await client.deleteResource(remotePath);
          await temp.delete(recursive: true);
        }
      } finally {
        navigator.popUntil((route) => route.isFirst);
        await tester.pump(const Duration(milliseconds: 400));
        await store.remove(connection.id);
        workspace.selectSection(ProductSection.transfer);
      }
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
