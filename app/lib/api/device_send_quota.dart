import 'dart:convert';

import 'package:http/http.dart' as http;

class DeviceSendBucketQuota {
  final int used;
  final int limit;
  final int remaining;
  final int retryAfterMs;

  const DeviceSendBucketQuota({
    required this.used,
    required this.limit,
    required this.remaining,
    required this.retryAfterMs,
  });

  factory DeviceSendBucketQuota.fromJson(Map<String, dynamic>? json, {required int fallbackLimit}) {
    if (json == null) {
      return DeviceSendBucketQuota(
        used: 0,
        limit: fallbackLimit,
        remaining: fallbackLimit,
        retryAfterMs: 0,
      );
    }
    final limit = _asInt(json['limit']) ?? fallbackLimit;
    final used = _asInt(json['used']) ?? 0;
    final remaining = _asInt(json['remaining']) ?? (limit - used).clamp(0, limit).toInt();
    return DeviceSendBucketQuota(
      used: used,
      limit: limit,
      remaining: remaining,
      retryAfterMs: _asInt(json['retryAfterMs']) ?? 0,
    );
  }

  bool get exhausted => remaining <= 0;
}

class DeviceSendQuota {
  final DeviceSendBucketQuota message;
  final DeviceSendBucketQuota signaling;
  /// Bucket charged by the last request: `message`, `signaling`, or null.
  final String? kind;
  final bool limited;
  final int hitSeq;

  const DeviceSendQuota({
    required this.message,
    required this.signaling,
    this.kind,
    this.limited = false,
    this.hitSeq = 0,
  });

  factory DeviceSendQuota.fromJson(
    Map<String, dynamic> json, {
    bool limited = false,
    int hitSeq = 0,
  }) {
    return DeviceSendQuota(
      message: DeviceSendBucketQuota.fromJson(
        json['message'] is Map ? Map<String, dynamic>.from(json['message'] as Map) : null,
        fallbackLimit: 90,
      ),
      signaling: DeviceSendBucketQuota.fromJson(
        json['signaling'] is Map ? Map<String, dynamic>.from(json['signaling'] as Map) : null,
        fallbackLimit: 600,
      ),
      kind: json['kind']?.toString(),
      limited: limited || json['error']?.toString() == 'rate_limited',
      hitSeq: hitSeq,
    );
  }

  DeviceSendQuota copyWith({
    DeviceSendBucketQuota? message,
    DeviceSendBucketQuota? signaling,
    String? kind,
    bool? limited,
    int? hitSeq,
  }) {
    return DeviceSendQuota(
      message: message ?? this.message,
      signaling: signaling ?? this.signaling,
      kind: kind ?? this.kind,
      limited: limited ?? this.limited,
      hitSeq: hitSeq ?? this.hitSeq,
    );
  }

  bool get anyExhausted => message.exhausted || signaling.exhausted;

  int get retryAfterSeconds {
    final ms = kind == 'signaling' ? signaling.retryAfterMs : message.retryAfterMs;
    final fallback = message.retryAfterMs > signaling.retryAfterMs
        ? message.retryAfterMs
        : signaling.retryAfterMs;
    final chosen = ms > 0 ? ms : fallback;
    return ((chosen + 999) ~/ 1000).clamp(1, 60);
  }
}

class DeviceSendRateLimitedException implements Exception {
  final DeviceSendQuota quota;
  DeviceSendRateLimitedException(this.quota);

  @override
  String toString() => 'rate_limited kind=${quota.kind}';
}

void Function(DeviceSendQuota quota)? onDeviceSendQuotaUpdate;

DeviceSendQuota? parseDeviceSendQuota({
  Map<String, String>? headers,
  String? body,
  bool limited = false,
  int hitSeq = 0,
}) {
  Map<String, dynamic>? json;
  final headerVal = headers == null
      ? null
      : (headers['x-device-send-quota'] ?? headers['X-Device-Send-Quota']);
  if (headerVal != null && headerVal.isNotEmpty) {
    try {
      final decoded = jsonDecode(headerVal);
      if (decoded is Map) json = Map<String, dynamic>.from(decoded);
    } catch (_) {}
  }
  if (json == null && body != null && body.isNotEmpty) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) json = Map<String, dynamic>.from(decoded);
    } catch (_) {}
  }
  if (json == null) return null;
  return DeviceSendQuota.fromJson(json, limited: limited, hitSeq: hitSeq);
}

void publishDeviceSendQuotaFromResponse(http.Response r) {
  final limited = r.statusCode == 429;
  final quota = parseDeviceSendQuota(
    headers: r.headers,
    body: r.body,
    limited: limited,
  );
  if (quota != null) onDeviceSendQuotaUpdate?.call(quota);
}

int? _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}
