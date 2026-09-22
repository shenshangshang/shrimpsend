import 'dart:io';
import 'package:flutter/services.dart';

/// Only metadata crosses the platform channel. File bytes go straight through
/// Dart's buffered file I/O into the MediaStore-owned Downloads destination.
class AndroidReceiveStorage {
  static const _channel = MethodChannel('dev.ultrasend/receive_storage');

  static Future<String?> prepare(String key, String name) async =>
      Platform.isAndroid
      ? _channel.invokeMethod<String>('prepare', {'key': key, 'name': name})
      : null;

  static Future<String?> lookup(String key) async => Platform.isAndroid
      ? _channel.invokeMethod<String>('lookup', {'key': key})
      : null;

  static Future<bool> owns(String path) async => Platform.isAndroid
      ? await _channel.invokeMethod<bool>('owns', {'path': path}) ?? false
      : false;

  static Future<String?> complete(String path, int expectedSize) async =>
      Platform.isAndroid
      ? _channel.invokeMethod<String>('complete', {
          'path': path,
          'expectedSize': expectedSize,
        })
      : null;
}
