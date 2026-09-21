import 'package:app/color_theme.dart';
import 'package:app/l10n/generated/app_localizations.dart';
import 'package:app/ui/app_ui.dart';
import 'package:app/ui/product_scaffold.dart';
import 'package:app/ui/product_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Page extends StatefulWidget {
  final String name;
  final Map<String, int> mounts;
  const _Page(this.name, this.mounts);
  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  final text = TextEditingController();
  @override
  void initState() {
    super.initState();
    widget.mounts.update(widget.name, (value) => value + 1, ifAbsent: () => 1);
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ProductScaffold(
    section: widget.name == '/'
        ? ProductSection.transfer
        : widget.name.startsWith('/files')
        ? ProductSection.files
        : ProductSection.settings,
    appBar: AppBar(title: Text(widget.name)),
    body: ListView(
      children: [
        TextField(key: ValueKey('input-${widget.name}'), controller: text),
        TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const ProductScaffold(body: Text('detail-page')),
            ),
          ),
          child: const Text('open-detail'),
        ),
      ],
    ),
  );
}

class _RootObserver extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
  }
}

void main() {
  Future<({Map<String, int> mounts, _RootObserver observer})> setup(
    WidgetTester tester, {
    Size size = const Size(1280, 800),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final mounts = <String, int>{};
    final observer = _RootObserver();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh', 'CN'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: buildAppTheme(
          colorTheme: AppColorTheme.emerald,
          brightness: Brightness.light,
        ),
        navigatorObservers: [observer],
        home: ProductWorkspace(
          transferBuilder: (_) => _Page('/', mounts),
          routes: {
            for (final path in [
              '/files',
              '/files/cloud',
              '/files/recent',
              '/files/favorites',
              '/settings',
              '/authorize',
              '/settings/fonts',
            ])
              path: (_) => _Page(path, mounts),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (mounts: mounts, observer: observer);
  }

  Future<void> select(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(ProductNavigation),
        matching: find.text(label),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'primary rail stays mounted and tab drafts survive repeated switches',
    (tester) async {
      final data = await setup(tester);
      final rail = tester.element(find.byType(ProductNavigation));
      final rect = tester.getRect(find.byType(ProductNavigation));
      await tester.enterText(
        find.byKey(const ValueKey('input-/')),
        'pending transfer draft',
      );
      await select(tester, '文件');
      await tester.enterText(
        find.byKey(const ValueKey('input-/files')),
        'report',
      );
      final fileState = tester.state(find.byType(_Page));
      await select(tester, '设置');
      await tester.enterText(
        find.byKey(const ValueKey('input-/settings')),
        'device name',
      );
      for (var i = 0; i < 3; i++) {
        await select(tester, '传输');
        expect(find.text('pending transfer draft'), findsOneWidget);
        await select(tester, '文件');
        expect(find.text('report'), findsOneWidget);
        expect(tester.state(find.byType(_Page)), same(fileState));
        await select(tester, '设置');
        expect(find.text('device name'), findsOneWidget);
        expect(tester.element(find.byType(ProductNavigation)), same(rail));
        expect(tester.getRect(find.byType(ProductNavigation)), rect);
      }
      expect(data.mounts, {'/': 1, '/files': 1, '/settings': 1});
      expect(data.observer.pushes, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'secondary sidebar stays fixed during file pages and detail transitions',
    (tester) async {
      final data = await setup(tester);
      await select(tester, '文件');
      final rail = tester.element(find.byType(ProductNavigation));
      final sidebar = tester.element(find.byType(ProductFilesSidebar));
      final rect = tester.getRect(find.byType(ProductFilesSidebar));
      await tester.tap(find.text('云端文件'));
      await tester.pumpAndSettle();
      expect(find.text('/files/cloud'), findsOneWidget);
      await tester.tap(find.text('open-detail'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 75));
      expect(tester.element(find.byType(ProductFilesSidebar)), same(sidebar));
      expect(tester.getRect(find.byType(ProductFilesSidebar)), rect);
      expect(tester.element(find.byType(ProductNavigation)), same(rail));
      await tester.pumpAndSettle();
      await select(tester, '设置');
      await select(tester, '文件');
      expect(find.text('detail-page'), findsOneWidget);
      await tester.tap(find.text('本机文件'));
      await tester.pumpAndSettle();
      expect(find.text('/files'), findsOneWidget);
      expect(find.text('detail-page'), findsNothing);
      expect(tester.element(find.byType(ProductFilesSidebar)), same(sidebar));
      expect(data.mounts['/files'], 1);
      expect(data.observer.pushes, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'settings navigation changes only its content and back restores its root',
    (tester) async {
      await setup(tester);
      await select(tester, '设置');
      final sidebar = tester.element(find.byType(ProductSettingsSidebar));
      await tester.tap(find.text('本机授权'));
      await tester.pumpAndSettle();
      expect(find.text('/authorize'), findsOneWidget);
      expect(
        tester.element(find.byType(ProductSettingsSidebar)),
        same(sidebar),
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('/settings'), findsOneWidget);
      expect(
        tester.element(find.byType(ProductSettingsSidebar)),
        same(sidebar),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'resizing to mobile keeps active content without duplicate navigation',
    (tester) async {
      final data = await setup(tester);
      await select(tester, '文件');
      await tester.enterText(
        find.byKey(const ValueKey('input-/files')),
        'keep on resize',
      );
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(find.byType(ProductNavigation), findsNothing);
      expect(find.byType(ProductBottomNavigation), findsOneWidget);
      expect(find.text('keep on resize'), findsOneWidget);
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(1280, 800);
      await tester.pumpAndSettle();
      expect(find.byType(ProductNavigation), findsOneWidget);
      expect(find.text('keep on resize'), findsOneWidget);
      expect(data.mounts['/files'], 1);
      expect(tester.takeException(), isNull);
    },
  );
}
