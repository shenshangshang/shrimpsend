import 'package:flutter/widgets.dart';

enum ProductSection { transfer, files, settings }

abstract class ProductWorkspaceController {
  Future<T?> openRoute<T extends Object?>(String route, {Object? arguments});
  void selectSection(ProductSection section);
}

/// Navigation belongs to the workspace, rather than to each destination page.
class ProductWorkspaceScope extends InheritedWidget {
  final ProductWorkspaceController controller;
  final ProductSection selected;

  const ProductWorkspaceScope({
    super.key,
    required this.controller,
    required this.selected,
    required super.child,
  });

  static ProductWorkspaceScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ProductWorkspaceScope>();

  @override
  bool updateShouldNotify(ProductWorkspaceScope oldWidget) =>
      controller != oldWidget.controller || selected != oldWidget.selected;
}

ProductSection productSectionForRoute(String route) {
  if (route == '/' || route == '/devices') return ProductSection.transfer;
  if (route.startsWith('/files') ||
      route.startsWith('/webdav') ||
      route == '/settings/webdav' ||
      route == '/settings/s3') {
    return ProductSection.files;
  }
  return ProductSection.settings;
}
