import 'dart:async';
import 'package:app/color_theme.dart';
import 'package:app/color_theme_store.dart';
import 'package:app/l10n/generated/app_localizations.dart';
import 'package:app/shortcut_preferences.dart';
import 'package:app/ui/app_ui.dart';
import 'package:app/widgets/chat/chat_composer.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    sendShortcutModeNotifier.value = SendShortcutMode.enter;
  });

  Future<void> mount(
    WidgetTester tester, {
    List<PlatformFile> files = const [],
    required Future<void> Function(String) send,
    VoidCallback? sendFiles,
    Size size = const Size(1100, 780),
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final history = InMemoryChatController();
    addTearDown(history.dispose);
    final store = ColorThemeStore();
    addTearDown(store.notifier.dispose);
    await tester.pumpWidget(
      ProviderScope(
        child: ColorThemeStoreScope(
          store: store,
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: buildAppTheme(
              colorTheme: AppColorTheme.emerald,
              brightness: brightness,
            ),
            home: Scaffold(
              body: Chat(
                currentUserId: 'this-device',
                chatController: history,
                resolveUser: (id) async => User(id: id),
                builders: Builders(
                  composerBuilder: (_) => ChatComposer(
                    onSend: send,
                    onAttachmentChoice: (_) async {},
                    pendingFiles: files,
                    onSendPendingFiles: sendFiles ?? () {},
                    onRemovePendingFile: (_) {},
                    onClearPendingFiles: () {},
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'one send action dispatches pending files and text without duplicates',
    (tester) async {
      final sent = <String>[];
      var fileSends = 0;
      final finish = Completer<void>();
      await mount(
        tester,
        files: [PlatformFile(name: '中文资料.pdf', size: 1024)],
        send: (text) {
          sent.add(text);
          return finish.future;
        },
        sendFiles: () => fileSends++,
      );
      expect(find.text('发送'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '这是说明文字');
      await tester.tap(find.widgetWithText(FilledButton, '发送'));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(sent, ['这是说明文字']);
      expect(fileSends, 1);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      finish.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Chinese composition is not sent and Shift Enter keeps a newline', (
    tester,
  ) async {
    final sent = <String>[];
    await mount(
      tester,
      send: (text) async {
        sent.add(text);
      },
    );
    await tester.showKeyboard(find.byType(TextField));
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: '中文',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 0, end: 2),
      ),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(sent, isEmpty);
    await tester.enterText(find.byType(TextField), '第一行');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(sent, isEmpty);
    // The native text input system commits the newline after the unhandled key.
    await tester.enterText(find.byType(TextField), '第一行\n');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(sent, ['第一行']);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'narrow $brightness composer keeps file and send controls visible',
      (tester) async {
        await mount(
          tester,
          size: const Size(390, 844),
          brightness: brightness,
          files: [PlatformFile(name: '很长的中文文件名用于检查窄屏排版资料.pdf', size: 4096)],
          send: (_) async {},
        );
        final send = tester.getRect(find.widgetWithText(FilledButton, '发送'));
        final file = tester.getRect(find.text('文件'));
        expect(send.right, lessThanOrEqualTo(390));
        expect(send.bottom, lessThanOrEqualTo(844));
        expect(file.left, greaterThanOrEqualTo(0));
        expect(tester.takeException(), isNull);
      },
    );
  }
}
