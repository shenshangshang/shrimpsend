import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

IconData deviceGlyph(String? platform, [String name = '']) {
  final kind = '${platform ?? ''} $name'.toLowerCase();
  if (RegExp('ipad|tablet').hasMatch(kind)) return LucideIcons.tablet;
  if (RegExp('ios|iphone|android|harmony').hasMatch(kind)) {
    return LucideIcons.smartphone;
  }
  if (RegExp('windows|linux').hasMatch(kind)) return LucideIcons.monitor;
  return LucideIcons.laptop;
}

String conversationDeviceName(
  String name,
  String deviceId, [
  String? platform,
]) {
  if (name.isNotEmpty &&
      name != deviceId &&
      !RegExp(
        r'^[a-z]+_[a-f\d-]+(?:…|\.\.\.)?$',
        caseSensitive: false,
      ).hasMatch(name)) {
    return name;
  }
  final kind = '${platform ?? ''} $deviceId'.toLowerCase();
  final label = kind.contains('macos')
      ? 'Mac'
      : kind.contains('windows')
      ? 'Windows'
      : kind.contains('ios')
      ? 'iPhone'
      : kind.contains('android')
      ? 'Android'
      : kind.contains('linux')
      ? 'Linux'
      : kind.contains('chrome')
      ? 'Chrome'
      : kind.contains('safari')
      ? 'Safari'
      : kind.contains('edge')
      ? 'Edge'
      : 'Web';
  final token = deviceId.split('_').skip(1).firstOrNull?.replaceAll('-', '');
  final suffix = token != null && token.length >= 4
      ? token.substring(token.length - 4).toUpperCase()
      : null;
  return suffix == null ? label : '$label · $suffix';
}
