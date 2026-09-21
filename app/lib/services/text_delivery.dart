import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

enum TextDeliveryChannel { lan, server }

/// Text routing follows device reachability, independently of account login.
/// A stale LAN address must not prevent delivery through device signaling.
class TextDelivery {
  static Future<TextDeliveryChannel> send({
    required Map<String, dynamic> envelope,
    required Iterable<String> lanUrls,
    required Future<void> Function(Map<String, dynamic>) sendToServer,
    String? fromDeviceName,
    http.Client? client,
    Duration lanTimeout = const Duration(seconds: 3),
    Duration serverTimeout = const Duration(seconds: 12),
  }) async {
    final payload = envelope['payload'] as Map;
    final body = jsonEncode({
      'text': payload['text'],
      'localId': payload['localId'],
      'textId': payload['textId'],
      'ts': envelope['ts'],
      'fromDeviceId': envelope['fromDeviceId'],
      'fromDeviceName': fromDeviceName,
      'toDeviceId': envelope['toDeviceId'],
    });
    for (final url in lanUrls.where((url) => url.trim().isNotEmpty).toSet()) {
      final transport = client ?? http.Client();
      try {
        final base = Uri.parse(url);
        if (!base.hasAuthority || !['http', 'https'].contains(base.scheme)) {
          continue;
        }
        final response = await transport
            .post(
              base.replace(path: '/message', query: null, fragment: null),
              headers: {'Content-Type': 'application/json; charset=utf-8'},
              body: body,
            )
            .timeout(lanTimeout);
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return TextDeliveryChannel.lan;
        }
      } catch (_) {
        // Try the next known address, then the device-authenticated server.
      } finally {
        if (client == null) transport.close();
      }
    }
    await sendToServer(envelope).timeout(serverTimeout);
    return TextDeliveryChannel.server;
  }
}
