import 'package:flutter/material.dart';

import 'app_ui.dart';
import 'product_scaffold.dart';
import 'product_workspace_scope.dart';

/// One persistent navigation rail with an independent, retained stack per area.
/// Detail navigation is confined to the content pane, outside both sidebars.
class ProductWorkspace extends StatefulWidget {
  final WidgetBuilder transferBuilder;
  final Map<String, WidgetBuilder> routes;
  final bool showTransferMobileNavigation;

  const ProductWorkspace({
    super.key,
    required this.transferBuilder,
    required this.routes,
    this.showTransferMobileNavigation = true,
  });

  @override
  State<ProductWorkspace> createState() => ProductWorkspaceState();
}

class ProductWorkspaceState extends State<ProductWorkspace>
    implements ProductWorkspaceController {
  static const _roots = ['/', '/files', '/settings'];
  final _keys = List.generate(3, (_) => GlobalKey<NavigatorState>());
  final _visited = <int>{0};
  final _locations = [..._roots];
  late final _observers = List.generate(
    3,
    (index) => _WorkspaceObserver((location) {
      if (location == null || _locations[index] == location) return;
      _locations[index] = location;
      // Navigator notifications can arrive during its build/layout phase.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }),
  );
  final _heroes = List.generate(3, (_) => HeroController());
  ProductSection _selected = ProductSection.transfer;

  @override
  void selectSection(ProductSection section) {
    if (_selected == section) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _selected = section;
      _visited.add(section.index);
    });
  }

  @override
  Future<T?> openRoute<T extends Object?>(
    String route, {
    Object? arguments,
  }) async {
    final section = productSectionForRoute(route);
    final index = section.index;
    selectSection(section);
    if (_keys[index].currentState == null) {
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted) return null;
    final navigator = _keys[index].currentState;
    if (navigator == null) return null;
    if (_observers[index].currentName == route) return null;
    // Sidebar destinations do not accumulate a new route on each click.
    // Preserve the branch's root (and its search/scroll state).
    navigator.popUntil((page) => page.isFirst);
    if (route == _roots[index]) return null;
    return navigator.pushNamed<T>(route, arguments: arguments);
  }

  String get _settingsLocation {
    final route = _locations[ProductSection.settings.index];
    if (route == '/authorize' ||
        route == '/account' ||
        route == '/settings/membership') {
      return route;
    }
    if ([
      '/settings/help',
      '/settings/version-history',
      '/settings/app-log',
      '/settings/feedback',
    ].contains(route)) {
      return '/settings/help';
    }
    return '/settings';
  }

  Widget _branch(int index, bool wide) {
    if (!_visited.contains(index)) return const SizedBox.shrink();
    final section = ProductSection.values[index];
    final active = section == _selected;
    final location = _locations[index];
    return TickerMode(
      enabled: section == _selected,
      child: FocusScope(
        canRequestFocus: section == _selected,
        child: Row(
          children: [
            if (section != ProductSection.transfer)
              Offstage(
                offstage: !wide,
                child: section == ProductSection.settings
                    ? ProductSettingsSidebar(location: _settingsLocation)
                    : ProductFilesSidebar(
                        location: location.startsWith('/files')
                            ? location
                            : '/files/connections',
                      ),
              ),
            Expanded(
              child: NavigatorPopHandler<Object?>(
                enabled: section == _selected,
                onPopWithResult: (result) {
                  if (active) _keys[index].currentState?.maybePop(result);
                },
                child: HeroControllerScope(
                  controller: _heroes[index],
                  child: Navigator(
                    key: _keys[index],
                    initialRoute: _roots[index],
                    observers: [_observers[index]],
                    // Avoid implicit '/' ancestors for '/files' and '/settings'.
                    onGenerateInitialRoutes: (_, __) => [
                      _route(index, RouteSettings(name: _roots[index])),
                    ],
                    onGenerateRoute: (settings) => _route(index, settings),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Route<dynamic> _route(int index, RouteSettings settings) {
    final builder = settings.name == '/'
        ? widget.transferBuilder
        : widget.routes[settings.name];
    if (builder == null) {
      throw FlutterError('Unknown product route: ${settings.name}');
    }
    return PageRouteBuilder<dynamic>(
      settings: settings,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (context, _, __) => builder(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 768;
    return ProductWorkspaceScope(
      controller: this,
      selected: _selected,
      child: Builder(
        builder: (context) => PopScope(
          canPop: _selected == ProductSection.transfer,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop &&
                !(_keys[_selected.index].currentState?.canPop() ?? false)) {
              selectSection(ProductSection.transfer);
            }
          },
          child: Material(
            color: context.appColors.background,
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Offstage(
                        offstage: !wide,
                        child: ProductNavigation(
                          selected: _selected,
                          onTransfer: () =>
                              selectSection(ProductSection.transfer),
                          onFiles: () => selectSection(ProductSection.files),
                          onSettings: () =>
                              selectSection(ProductSection.settings),
                        ),
                      ),
                      Expanded(
                        child: IndexedStack(
                          index: _selected.index,
                          children: List.generate(
                            3,
                            (index) => _branch(index, wide),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!wide &&
                    (_selected != ProductSection.transfer ||
                        widget.showTransferMobileNavigation))
                  ProductBottomNavigation(
                    selected: _selected.index,
                    onSelected: (index) =>
                        selectSection(ProductSection.values[index]),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkspaceObserver extends NavigatorObserver {
  final ValueChanged<String?> onLocation;
  String? currentName;
  _WorkspaceObserver(this.onLocation);
  void _changed(Route<dynamic>? route) {
    currentName = route?.settings.name;
    onLocation(currentName);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _changed(route);
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _changed(previousRoute);
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _changed(newRoute);
}
