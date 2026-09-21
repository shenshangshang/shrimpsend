import 'dart:io';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:app/api/device_licenses.dart';
import 'package:app/color_theme.dart';
import 'package:app/color_theme_store.dart';
import 'package:app/font_size_store.dart';
import 'package:app/l10n/generated/app_localizations.dart';
import 'package:app/preferences/locale_region_store.dart';
import 'package:app/screens/account_screen.dart';
import 'package:app/screens/device_authorization_screen.dart';
import 'package:app/screens/file_connections_screen.dart';
import 'package:app/screens/font_settings_screen.dart';
import 'package:app/screens/login_screen.dart';
import 'package:app/screens/product_feedback_screen.dart';
import 'package:app/screens/settings_screen.dart';
import 'package:app/screens/shortcut_settings_screen.dart';
import 'package:app/screens/webdav_connection_screen.dart';
import 'package:app/screens/webdav_settings_screen.dart';
import 'package:app/theme_store.dart';
import 'package:app/ui/app_ui.dart';
import 'package:app/services/file_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _License extends DeviceLicenseApi {
  @override Future<Map<String,dynamic>> mine() async => {'authorized':false,'status':'FREE'};
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final pages = <String,Widget Function()>{
    'general': () => const SettingsScreen(),
    'receiving': () => const SettingsScreen(initialTab:'receiving'),
    'appearance': () => const SettingsScreen(initialTab:'appearance'),
    'language': () => const SettingsScreen(initialTab:'language'),
    'fonts': () => const FontSettingsScreen(),
    'shortcuts': () => const ShortcutSettingsScreen(),
    'authorize': () => DeviceAuthorizationScreen(api:_License()),
    'account': () => const AccountScreen(),
    'login': () => const LoginScreen(),
    'feedback': () => const ProductFeedbackScreen(),
    'cloud': () => const WebDavSettingsScreen(),
    'connection': () => const WebDavConnectionScreen(),
    'connections': () => const FileConnectionsScreen(),
  };
  for (final (variant,size,brightness) in [
    ('desktop', const Size(1280,800), Brightness.light),
    ('dark', const Size(1280,800), Brightness.dark),
    ('mobile', const Size(390,844), Brightness.light),
  ]) {
    for (final entry in pages.entries) {
      testWidgets('${entry.key} renders without overflow at $variant size', (tester) async {
        final temp = Directory.systemTemp.createTempSync('shrimpsend-layout-');
        addTearDown(() => temp.deleteSync(recursive:true));
        SharedPreferences.setMockInitialValues({'ultrasend_custom_save_dir':temp.path, 'device_name':'Mac · 设计验证'});
        FileStore.invalidateReceiveDirCache();
        tester.view.physicalSize = size; tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
        final colors = ColorThemeStore(); final fonts = FontSizeStore(); final theme = ThemeStore(); final locale = LocaleRegionStore();
        final output = Platform.environment['REDESIGN_QA_OUTPUT'];
        if (output != null) {
          final loader = FontLoader('ProductQA')..addFont(Future.value(ByteData.sublistView(File('assets/fonts/windows/WenYuanSansSCVF.ttf').readAsBytesSync())));
          await loader.load();
        }
        final key = GlobalKey();
        var appTheme = buildAppTheme(colorTheme:AppColorTheme.emerald, brightness:brightness);
        if (output != null) appTheme = appTheme.copyWith(textTheme:appTheme.textTheme.apply(fontFamily:'ProductQA'));
        await tester.pumpWidget(ProviderScope(child: ThemeStoreScope(store:theme, child: ColorThemeStoreScope(store:colors, child: FontSizeStoreScope(store:fonts, child: LocaleRegionStoreScope(store:locale, child: MaterialApp(locale:const Locale('zh','CN'), localizationsDelegates:AppLocalizations.localizationsDelegates, supportedLocales:AppLocalizations.supportedLocales, theme:appTheme, home:RepaintBoundary(key:key,child:entry.value()))))))));
        await tester.pump(); await tester.pump(const Duration(milliseconds:800));
        expect(tester.takeException(), isNull);
        if (output != null) {
          await tester.runAsync(() async {
            final image = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
            final bytes = await image.toByteData(format:ui.ImageByteFormat.png);
            final file = File('$output/flutter-${entry.key}-$variant.png');
            await file.parent.create(recursive:true); await file.writeAsBytes(bytes!.buffer.asUint8List()); image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox()); await tester.pump();
      });
    }
  }
}
