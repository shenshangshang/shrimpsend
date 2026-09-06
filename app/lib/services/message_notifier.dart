import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:window_manager/window_manager.dart';

import '../logger.dart';

/// System notifications for messages arriving while the app is not showing
/// the sender's conversation (backgrounded, minimized or screen off).
///
/// - Android/iOS: flutter_local_notifications with a high-importance channel
///   (heads-up) and the POST_NOTIFICATIONS runtime request on Android 13+.
/// - Windows: local_notifier toast; clicking it brings the window back.
class MessageNotifier {
  MessageNotifier._();

  static final instance = MessageNotifier._();

  static const _androidChannelId = 'new_messages';
  static const _androidChannelName = '新消息';

  bool _initialized = false;
  FlutterLocalNotificationsPlugin? _mobilePlugin;

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final plugin = FlutterLocalNotificationsPlugin();
        const android = AndroidInitializationSettings('@mipmap/ic_launcher');
        const ios = DarwinInitializationSettings();
        await plugin.initialize(
          settings: const InitializationSettings(android: android, iOS: ios),
        );
        if (Platform.isAndroid) {
          final impl = plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
          await impl?.createNotificationChannel(
            const AndroidNotificationChannel(
              _androidChannelId,
              _androidChannelName,
              description: '收到文本消息和文件时的提醒',
              importance: Importance.high,
            ),
          );
          // Android 13+ blocks notifications until granted at runtime.
          await impl?.requestNotificationsPermission();
        }
        _mobilePlugin = plugin;
      } else if (Platform.isWindows) {
        await localNotifier.setup(
          appName: 'dev.ultrasend.app',
          shortcutPolicy: ShortcutPolicy.requireCreate,
        );
      }
    } catch (e) {
      _initialized = false;
      logChat.warning('MessageNotifier init failed: $e');
    }
  }

  /// Shows a heads-up/toast notification. Best-effort: failures are logged
  /// and swallowed so callers never break message handling.
  Future<void> showMessage({
    required String title,
    required String body,
  }) async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        await ensureInitialized();
        final plugin = _mobilePlugin;
        if (plugin == null) return;
        await plugin.show(
          id: DateTime.now().millisecondsSinceEpoch ~/ 1000 % 0x7fffffff,
          title: title,
          body: body,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              _androidChannelId,
              _androidChannelName,
              channelDescription: '收到文本消息和文件时的提醒',
              importance: Importance.high,
              priority: Priority.high,
              category: AndroidNotificationCategory.message,
            ),
          ),
        );
      } else if (Platform.isWindows) {
        await ensureInitialized();
        final notification = LocalNotification(title: title, body: body);
        notification.onClick = () {
          windowManager.show();
          windowManager.focus();
        };
        await notification.show();
      }
    } catch (e) {
      logChat.warning('MessageNotifier show failed: $e');
    }
  }
}
