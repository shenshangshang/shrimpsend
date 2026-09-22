import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Centralizes platform classification used by membership / payment / transfer.
///
/// Keep this module free of Flutter widget imports so it can be referenced from
/// pure-Dart logic (e.g. `membership_channel_guard.dart`) and easily faked in tests.
class RuntimePlatform {
  RuntimePlatform._();

  /// HarmonyOS NEXT / OpenHarmony Flutter embedding (`Platform.operatingSystem`
  /// is `ohos` on the community SDK).
  static bool get isOhos {
    if (kIsWeb) return false;
    final os = Platform.operatingSystem.toLowerCase();
    return os == 'ohos' || os == 'harmonyos';
  }

  /// macOS / Windows / Linux desktop (Flutter desktop embedding).
  static bool get isDesktop {
    if (kIsWeb) return false;
    return Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  }

  static bool get isMobile {
    if (kIsWeb) return false;
    return Platform.isIOS || Platform.isAndroid || isOhos;
  }

  static bool get isIos => !kIsWeb && Platform.isIOS;
  static bool get isAndroid => !kIsWeb && Platform.isAndroid;
  static bool get isMacOS => !kIsWeb && Platform.isMacOS;
  static bool get isWindows => !kIsWeb && Platform.isWindows;
  static bool get isLinux => !kIsWeb && Platform.isLinux;

  /// Canonical OS name for device register, LAN TXT, and link strategy.
  /// HarmonyOS is always `harmonyos` (never raw `ohos`).
  static String get osName {
    if (kIsWeb) return 'web';
    if (isOhos) return 'harmonyos';
    return Platform.operatingSystem;
  }

  /// Tag passed to backend `success_url` / order creation so the post-payment page
  /// can hint "return to your app" when paid from desktop.
  static String get platformTag {
    if (kIsWeb) return 'web';
    if (isOhos) return 'harmonyos';
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    if (Platform.isMacOS) return 'desktop-macos';
    if (Platform.isWindows) return 'desktop-windows';
    if (Platform.isLinux) return 'desktop-linux';
    return 'unknown';
  }
}

/// HarmonyOS feature gates until community plugins land. Other platforms: all on.
class OhosCapabilities {
  OhosCapabilities._();

  static bool get lanMdns => !RuntimePlatform.isOhos;
  static bool get webrtc => !RuntimePlatform.isOhos;
  static bool get inboundShare => !RuntimePlatform.isOhos;
  static bool get nativeStoreIap => !RuntimePlatform.isOhos;
  static bool get photoManagerPicker => !RuntimePlatform.isOhos;
  static bool get apkInstall => !RuntimePlatform.isOhos;

  /// S3 / HTTP cloud relay is pure Dart and is the HarmonyOS file path for now.
  static bool get s3Cloud => true;

  /// LAN HTTP server uses `dart:io`; mDNS discovery is separate ([lanMdns]).
  static bool get lanHttp => true;
}
