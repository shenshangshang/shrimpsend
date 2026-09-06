import 'dart:convert';
import 'package:http/http.dart' as http;
import '../logger.dart';
import 'client.dart';

/// One iceServers entry as passed to flutter_webrtc's createPeerConnection.
class IceServerConfig {
  final List<String> urls;
  final String? username;
  final String? credential;

  IceServerConfig({required this.urls, this.username, this.credential});

  Map<String, dynamic> toMap() => {
        'urls': urls,
        if (username != null && username!.isNotEmpty) 'username': username,
        if (credential != null && credential!.isNotEmpty) 'credential': credential,
      };
}

class WebrtcIceConfig {
  final List<IceServerConfig> iceServers;
  final bool turnEnabled;
  final String? tier;

  WebrtcIceConfig({
    required this.iceServers,
    required this.turnEnabled,
    this.tier,
  });
}

/// GET /api/webrtc/config. Returns null on any failure so callers keep
/// their fallback STUN set without breaking session setup.
Future<WebrtcIceConfig?> fetchWebrtcConfig() async {
  try {
    return await withAuthRetry(() async {
      final r = await http
          .get(
            Uri.parse('$apiBaseUrl/api/webrtc/config'),
            headers: apiHeaders,
          )
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return null;
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      final list = (data['iceServers'] as List? ?? const [])
          .whereType<Map>()
          .map((e) {
            final urls =
                (e['urls'] as List? ?? const []).map((v) => v.toString()).toList();
            if (urls.isEmpty) return null;
            return IceServerConfig(
              urls: urls,
              username: e['username'] as String?,
              credential: e['credential'] as String?,
            );
          })
          .whereType<IceServerConfig>()
          .toList();
      return WebrtcIceConfig(
        iceServers: list,
        turnEnabled: data['turnEnabled'] == true,
        tier: data['tier'] as String?,
      );
    });
  } catch (e) {
    logApi.warning('fetchWebrtcConfig failed: $e');
    return null;
  }
}

/// Process-wide ICE server store shared by WebRTC sessions and probes.
/// Refreshed at most every 10 minutes; failures keep the last known set.
class IceServersStore {
  static const List<Map<String, dynamic>> _fallback = [
    {'urls': ['stun:stun.miwifi.com:3478']},
    {'urls': ['stun:stun.qq.com:3478']},
    {'urls': ['stun:stun.l.google.com:19302']},
  ];

  static List<Map<String, dynamic>> _current = List.of(_fallback);
  static DateTime _refreshedAt = DateTime.fromMillisecondsSinceEpoch(0);
  static bool turnEnabled = false;
  static String? tier;

  static List<Map<String, dynamic>> get currentSync => _current;
  static bool get isDefault => identical(_current, _fallback);

  static Future<List<Map<String, dynamic>>> current() async {
    final now = DateTime.now();
    if (now.difference(_refreshedAt) < const Duration(minutes: 10)) {
      return _current;
    }
    // Throttle even on failure so a dead backend does not get polled per session.
    _refreshedAt = now;
    final cfg = await fetchWebrtcConfig();
    if (cfg != null && cfg.iceServers.isNotEmpty) {
      _current = cfg.iceServers.map((e) => e.toMap()).toList();
      turnEnabled = cfg.turnEnabled;
      tier = cfg.tier;
    }
    return _current;
  }
}
