import 'package:flutter/widgets.dart';
import '../screens/transfer_activity_screen.dart';
import '../screens/file_connections_screen.dart';
import '../screens/device_authorization_screen.dart';
import '../screens/login_screen.dart';
import '../screens/devices_screen.dart';
import '../screens/file_manager_screen.dart';
import '../screens/account_screen.dart';
import '../screens/product_feedback_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/font_settings_screen.dart';
import '../screens/shortcut_settings_screen.dart';
import '../screens/s3_settings_screen.dart';
import '../screens/webdav_settings_screen.dart';
import '../screens/webdav_connection_screen.dart';
import '../screens/version_history_screen.dart';
import '../screens/app_log_screen.dart';
import '../screens/membership_screen.dart';
import '../screens/device_identity_screen.dart';

/// Shared builders for the root router and the workspace content navigators.
final Map<String, WidgetBuilder> productRoutes = {
  '/login': (_) => const LoginScreen(),
  '/files': (_) => const FileManagerScreen(),
  '/files/tasks': (_) => const TransferActivityScreen(),
  '/files/recent': (_) => const FileManagerScreen(initialView: '/files/recent'),
  '/files/favorites': (_) =>
      const FileManagerScreen(initialView: '/files/favorites'),
  '/files/cloud': (_) => const WebDavSettingsScreen(),
  '/files/connections': (_) => const FileConnectionsScreen(),
  '/settings': (_) => const SettingsScreen(),
  '/settings/device-identity': (_) => const DeviceIdentityScreen(),
  '/settings/help': (_) => const SettingsScreen(help: true),
  '/settings/receiving': (_) => const SettingsScreen(initialTab: 'receiving'),
  '/settings/appearance': (_) => const SettingsScreen(initialTab: 'appearance'),
  '/settings/language': (_) => const SettingsScreen(initialTab: 'language'),
  '/authorize': (_) => const DeviceAuthorizationScreen(),
  '/settings/membership': (_) => const MembershipScreen(),
  '/settings/s3': (_) => const S3SettingsScreen(),
  '/settings/webdav': (_) => const WebDavSettingsScreen(),
  '/webdav/add': (_) => const WebDavConnectionScreen(),
  '/settings/shortcuts': (_) => const ShortcutSettingsScreen(),
  '/settings/fonts': (_) => const FontSettingsScreen(),
  '/settings/version-history': (_) => const VersionHistoryScreen(),
  '/settings/app-log': (_) => const AppLogScreen(),
  '/devices': (_) => const DevicesScreen(),
  '/account': (_) => const AccountScreen(),
  '/settings/feedback': (_) => const ProductFeedbackScreen(),
};
