import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../device_id.dart';
import '../logger.dart';
import '../utils/runtime_platform.dart';
import '../services/device_identity_store.dart';
import 'client.dart';

class RealtimeTokenResponse {
  final String uid;
  final String token;
  final String websocketUrl;
  final int deviceFlag;
  final int deviceLevel;
  final String channelId;
  final int channelType;
  final String? deviceAccessToken;

  RealtimeTokenResponse({
    required this.uid,
    required this.token,
    required this.websocketUrl,
    required this.deviceFlag,
    required this.deviceLevel,
    required this.channelId,
    required this.channelType,
    this.deviceAccessToken,
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
        deviceAccessToken: j['deviceAccessToken'] as String?,
      );
}

Future<RealtimeTokenResponse> getRealtimeToken({
  required String deviceId,
  required String platform,
}) async {
  return createDeviceSession(deviceId: deviceId, platform: platform);
}

Future<RealtimeTokenResponse> createDeviceSession({
  required String deviceId,
  required String platform,
}) async {
  logApi.info('createDeviceSession deviceId=$deviceId platform=$platform');
  final secret = await getOrCreateDeviceSecret();
  final identity = await getDeviceIdentityStore();
  if (identity.status.value == DeviceIdentityStatus.recoveryRequired) {
    throw const DeviceIdentityException('recovery_required');
  }
  final r = await http.post(
    Uri.parse('$apiBaseUrl/api/realtime/device-session'),
    headers: jsonHeadersOnly,
    body: jsonEncode({
      'deviceId': deviceId,
      'deviceSecret': secret,
      'platform': platform,
    }),
  ).timeout(const Duration(seconds: 12));
  if (r.statusCode < 200 || r.statusCode >= 300) {
    if (r.statusCode == 401 && r.body.contains('device secret mismatch')) {
      identity.requireRecovery();
      throw const DeviceIdentityException('recovery_required');
    }
    throw Exception(errorMessageFromResponse(r, '获取连接凭证失败'));
  }
  identity.sessionVerified();
  final res = RealtimeTokenResponse.fromJson(
    jsonDecode(r.body) as Map<String, dynamic>,
  );
  if (res.deviceAccessToken != null && res.deviceAccessToken!.isNotEmpty) {
    setDeviceAccessToken(res.deviceAccessToken);
    setDeviceSessionRenewal(() async {
      await createDeviceSession(deviceId: deviceId, platform: platform);
    });
  }
  logApi.info(
    'createDeviceSession success uid=${res.uid} flag=${res.deviceFlag} ws=${res.websocketUrl}',
  );
  return res;
}

String realtimePlatformName() {
  if (kIsWeb) return 'web';
  if (RuntimePlatform.isOhos) return 'harmonyos';
  return defaultTargetPlatform.name;
}
