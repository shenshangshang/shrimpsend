import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../preferences/locale_region_store.dart';
import '../providers/device_provider.dart';
import '../ui/product_routes.dart';
import '../ui/product_workspace.dart';
import 'chat_screen.dart';

/// Open directly into transfers. Language/region already have build defaults;
/// account login and preference changes remain available from settings.
class AppEntryScreen extends ConsumerWidget {
  const AppEntryScreen({
    super.key,
    required this.localeRegionStore,
    this.initialOfflineWithoutLogin = false,
  });

  final LocaleRegionStore localeRegionStore;
  final bool initialOfflineWithoutLogin;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ProductWorkspace(
    routes: productRoutes,
    transferBuilder: (_) => const ChatScreen(),
    showTransferMobileNavigation: ref.watch(selectedDeviceIdProvider) == null,
  );
}
