import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../logger.dart';
import '../utils/runtime_platform.dart';
import 'client.dart';

class RealtimeTokenResponse {
  final String uid;
  final String token;
  final String websocketUrl;
  final int deviceFlag;
  final int deviceLevel;
  final String channelId;
  final int channelType;

  RealtimeTokenResponse({
    required this.uid,
    required this.token,
    required this.websocketUrl,
    required this.deviceFlag,
    required this.deviceLevel,
    required this.channelId,
    required this.channelType,
  });

  factory RealtimeTokenResponse.fromJson(Map<String, dynamic> j) =>
      RealtimeTokenResponse(
        uid: j['uid'] as String,
        token: j['token'] as String,
        websocketUrl: j['websocketUrl'] as String,
        deviceFlag: (j['deviceFlag'] as num?)?.toInt() ?? 0,
        deviceLevel: (j['deviceLevel'] as num?)?.toInt() ?? 0,
        channelId: j['channelId'] as String? ?? j['uid'] as String,
        channelType: (j['channelType'] as num?)?.toInt() ?? 1,
      );
}

Future<RealtimeTokenResponse> getRealtimeToken({
  required String deviceId,
  required String platform,
}) async {
  logApi.info('getRealtimeToken deviceId=$deviceId platform=$platform');
  return withAuthRetry(() async {
    final uri = Uri.parse('$apiBaseUrl/api/realtime/token').replace(
      queryParameters: {
        'deviceId': deviceId,
        'platform': platform,
      },
    );
    final r = await http.get(uri, headers: apiHeaders);
    checkAuthResponse(r, fallback: '获取连接凭证失败');
    final res = RealtimeTokenResponse.fromJson(
      jsonDecode(r.body) as Map<String, dynamic>,
    );
    logApi.info(
      'getRealtimeToken success uid=${res.uid} flag=${res.deviceFlag} ws=${res.websocketUrl}',
    );
    return res;
  });
}

String realtimePlatformName() {
  if (kIsWeb) return 'web';
  if (RuntimePlatform.isOhos) return 'harmonyos';
  return defaultTargetPlatform.name;
}
