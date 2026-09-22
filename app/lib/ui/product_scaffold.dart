import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'app_ui.dart';
import 'product_workspace_scope.dart';
export 'product_workspace_scope.dart'
    show ProductSection, ProductWorkspaceScope;

Future<T?> openProductRoute<T extends Object?>(
  BuildContext context,
  String route,
) async {
  final workspace = ProductWorkspaceScope.maybeOf(context);
  if (workspace != null) return workspace.controller.openRoute<T>(route);
  if (ModalRoute.of(context)?.settings.name == route) return null;
  if (route == '/') {
    Navigator.of(context).popUntil((route) => route.isFirst);
    return null;
  } else {
    return Navigator.of(context).pushNamed<T>(route);
  }
}

class ProductNavigation extends StatelessWidget {
  final ProductSection selected;
  final VoidCallback? onTransfer;
  final VoidCallback? onFiles;
  final VoidCallback? onSettings;
  const ProductNavigation({
    super.key,
    required this.selected,
    this.onTransfer,
    this.onFiles,
    this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    Widget item(
      ProductSection section,
      IconData icon,
      String label,
      VoidCallback onTap,
    ) {
      final active = selected == section;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Semantics(
          selected: active,
          button: true,
          label: label,
          child: Tooltip(
            message: label,
            child: Material(
              color: active ? colors.accentSoft : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 56,
                  height: 62,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icon,
                        size: 22,
                        color: active
                            ? Theme.of(context).colorScheme.primary
                            : colors.textSecondary,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 11,
                          color: active
                              ? Theme.of(context).colorScheme.primary
                              : colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      width: 72,
      decoration: BoxDecoration(
        color: colors.background,
        border: Border(right: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 22),
            Image.asset(
              'assets/logo.png',
              width: 32,
              height: 32,
              filterQuality: FilterQuality.high,
            ),
            const SizedBox(height: 5),
            Text(
              zh ? '虾传' : 'Shrimp',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 28),
            item(
              ProductSection.transfer,
              LucideIcons.send,
              zh ? '传输' : 'Transfer',
              onTransfer ?? () => openProductRoute(context, '/'),
            ),
            item(
              ProductSection.files,
              LucideIcons.folder,
              zh ? '文件' : 'Files',
              onFiles ?? () => openProductRoute(context, '/files'),
            ),
            const Spacer(),
            item(
              ProductSection.settings,
              LucideIcons.settings,
              zh ? '设置' : 'Settings',
              onSettings ?? () => openProductRoute(context, '/settings'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// Shared desktop chrome; narrow screens retain native back navigation.
class ProductScaffold extends StatelessWidget {
  final ProductSection section;
  final String settingsLocation;
  final String filesLocation;
  final PreferredSizeWidget? appBar;
  final Widget? body;
  final Color? backgroundColor;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Widget? bottomNavigationBar;
  final List<Widget>? persistentFooterButtons;
  final bool? resizeToAvoidBottomInset;
  final bool extendBody;
  final bool extendBodyBehindAppBar;
  final bool primary;
  final bool embedded;
  final Widget? sidebar;
  final String? preferencesTab;
  const ProductScaffold({
    super.key,
    this.section = ProductSection.settings,
    this.settingsLocation = '/settings',
    this.filesLocation = '/files',
    this.appBar,
    this.body,
    this.backgroundColor,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.bottomNavigationBar,
    this.persistentFooterButtons,
    this.resizeToAvoidBottomInset,
    this.extendBody = false,
    this.embedded = false,
    this.sidebar,
    this.preferencesTab,
    this.extendBodyBehindAppBar = false,
    this.primary = true,
  });

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 768 && !embedded;
    final content = preferencesTab == null
        ? body
        : Column(
            children: [
              ProductPreferencesTabs(selected: preferencesTab!),
              Expanded(child: body ?? const SizedBox.shrink()),
            ],
          );
    final page = Scaffold(
      appBar: appBar,
      body: content,
      backgroundColor: backgroundColor ?? context.appColors.surface,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      bottomNavigationBar: bottomNavigationBar,
      persistentFooterButtons: persistentFooterButtons,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      extendBody: extendBody,
      extendBodyBehindAppBar: extendBodyBehindAppBar,
      primary: primary,
    );
    if (!wide || ProductWorkspaceScope.maybeOf(context) != null) return page;
    return Material(
      color: context.appColors.background,
      child: Row(
        children: [
          ProductNavigation(selected: section),
          if (sidebar != null)
            sidebar!
          else if (section == ProductSection.settings)
            ProductSettingsSidebar(location: settingsLocation)
          else if (section == ProductSection.files)
            ProductFilesSidebar(location: filesLocation),
          Expanded(child: page),
        ],
      ),
    );
  }
}

class ProductPreferencesTabs extends StatelessWidget {
  final String selected;
  final ValueChanged<String>? onChanged;
  const ProductPreferencesTabs({
    super.key,
    required this.selected,
    this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final items = <(String, String)>[
      ('general', zh ? '通用' : 'General'),
      ('receiving', zh ? '接收与保存' : 'Receiving'),
      ('appearance', zh ? '外观' : 'Appearance'),
      ('language', zh ? '语言' : 'Language'),
      ('fonts', zh ? '字体' : 'Fonts'),
      ('shortcuts', zh ? '快捷键' : 'Shortcuts'),
    ];
    return Align(
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: items
              .map(
                (item) => Container(
                  margin: const EdgeInsets.only(right: 18),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: selected == item.$1
                            ? Theme.of(context).colorScheme.primary
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: selected == item.$1
                          ? Theme.of(context).colorScheme.primary
                          : context.appColors.textSecondary,
                    ),
                    onPressed: () {
                      if (onChanged != null) {
                        onChanged!(item.$1);
                      } else {
                        openProductRoute(
                          context,
                          item.$1 == 'general'
                              ? '/settings'
                              : '/settings/${item.$1}',
                        );
                      }
                    },
                    child: Text(item.$2, style: const TextStyle(fontSize: 13)),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class ProductSettingsSidebar extends StatelessWidget {
  final String location;
  const ProductSettingsSidebar({super.key, required this.location});
  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final colors = context.appColors;
    final items = <(String, String, IconData)>[
      ('/settings', zh ? '本机设置' : 'Device settings', LucideIcons.monitor),
      ('/authorize', zh ? '本机授权' : 'Authorization', LucideIcons.shieldCheck),
      (
        '/settings/membership',
        zh ? '会员与名额' : 'Membership & slots',
        LucideIcons.badgeCheck,
      ),
      ('/account', zh ? '账号' : 'Account', LucideIcons.userRound),
      ('/settings/help', zh ? '帮助' : 'Help', LucideIcons.circleHelp),
    ];
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        border: Border(right: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 28),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 26),
              child: Text(
                zh ? '设置' : 'Settings',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ...items.map((item) {
              final selected = item.$1 == location;
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: ListTile(
                  dense: true,
                  minTileHeight: 44,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  selected: selected,
                  selectedTileColor: colors.accentSoft,
                  selectedColor: Theme.of(context).colorScheme.primary,
                  leading: Icon(item.$3, size: 18),
                  title: Text(item.$2, style: const TextStyle(fontSize: 13)),
                  onTap: () => openProductRoute(context, item.$1),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class ProductBottomNavigation extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelected;
  const ProductBottomNavigation({
    super.key,
    required this.selected,
    required this.onSelected,
  });
  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final colors = context.appColors;
    return Material(
      color: colors.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: colors.border)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 64,
            child: Row(
              children: [
                for (final (index, icon, label) in [
                  (0, LucideIcons.send, zh ? '传输' : 'Transfer'),
                  (1, LucideIcons.folder, zh ? '文件' : 'Files'),
                  (2, LucideIcons.settings, zh ? '设置' : 'Settings'),
                ])
                  Expanded(
                    child: Semantics(
                      selected: selected == index,
                      button: true,
                      child: InkWell(
                        onTap: () => onSelected(index),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              icon,
                              size: 23,
                              color: selected == index
                                  ? Theme.of(context).colorScheme.primary
                                  : colors.textSecondary,
                            ),
                            const SizedBox(height: 5),
                            Text(
                              label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: selected == index
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: selected == index
                                    ? Theme.of(context).colorScheme.primary
                                    : colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ProductFilesSidebar extends StatelessWidget {
  final String location;
  final ValueChanged<String>? onLocalView;
  const ProductFilesSidebar({
    super.key,
    this.location = '/files',
    this.onLocalView,
  });
  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final colors = context.appColors;
    final items = [
      ('/files', zh ? '本机文件' : 'Local files', LucideIcons.folder),
      ('/files/cloud', zh ? '云端文件' : 'Cloud files', LucideIcons.cloud),
      ('/files/recent', zh ? '最近使用' : 'Recent files', LucideIcons.clock3),
      ('/files/favorites', zh ? '收藏' : 'Favorites', LucideIcons.star),
      ('/files/tasks', zh ? '传输任务' : 'Transfers', LucideIcons.arrowDownUp),
      (
        '/files/connections',
        zh ? '连接设置' : 'Connections',
        LucideIcons.settings2,
      ),
    ];
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        border: Border(right: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 28),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 26),
              child: Text(
                zh ? '文件' : 'Files',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: ListTile(
                  dense: true,
                  minTileHeight: 44,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  selected: location == item.$1,
                  selectedTileColor: colors.accentSoft,
                  selectedColor: Theme.of(context).colorScheme.primary,
                  leading: Icon(item.$3, size: 18),
                  title: Text(item.$2, style: const TextStyle(fontSize: 13)),
                  onTap: () {
                    if (onLocalView != null &&
                        [
                          '/files',
                          '/files/recent',
                          '/files/favorites',
                        ].contains(item.$1)) {
                      onLocalView!(item.$1);
                    } else {
                      openProductRoute(context, item.$1);
                    }
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
