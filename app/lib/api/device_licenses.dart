import 'dart:convert';
import 'package:http/http.dart' as http;
import '../device_id.dart';
import 'client.dart';
import 'realtime_token.dart';

String? licenseQrToken(String value) {
  try {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    final token = Uri.splitQueryString(uri.fragment)['license'];
    return token != null && RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(token)
        ? token
        : null;
  } on FormatException {
    return null;
  }
}

String deviceLicenseError(Object e, bool zh) {
  final key = e.toString().replaceFirst('Exception: ', '');
  const messages = {
    'license_no_slots': [
      '没有可用名额，请释放旧设备或购买设备服务包。',
      'No slots available. Release an old device or purchase a plan.',
    ],
    'license_invalid_code': [
      '授权码无效、已使用或已过期。',
      'The code is invalid, used or expired.',
    ],
    'license_code_claimed': [
      '此授权码已由另一台设备申请。',
      'Another device has already claimed this code.',
    ],
    'license_device_already_bound': [
      '本机已有授权，请先解除原授权。',
      'Release the existing authorization before assigning a new one.',
    ],
    'license_membership_expired': [
      '会员已到期，请联系购买者续费。',
      'Membership expired. Ask the purchaser to renew.',
    ],
    'license_too_many_attempts': [
      '操作过于频繁，请稍后再试。',
      'Too many attempts. Please try again later.',
    ],
  };
  return messages[key]?[zh ? 0 : 1] ??
      (zh
          ? '无法连接授权服务，请检查连接后重试。'
          : 'Cannot reach the authorization service. Check your connection.');
}

class DeviceLicenseApi {
  Future<Map<String, dynamic>> request(
    String path, {
    bool owner = false,
    String method = 'GET',
    Map<String, dynamic>? body,
  }) async {
    Future<Map<String, dynamic>> run() async {
      if (!owner && !hasDeviceAccessToken) {
        await createDeviceSession(
          deviceId: await getOrCreateDeviceId(),
          platform: realtimePlatformName(),
        );
      }
      Future<http.Response> send() async {
        final client = http.Client();
        try {
          final req = http.Request(
            method,
            Uri.parse('$apiBaseUrl/api/device-licenses$path'),
          );
          req.headers.addAll(owner ? apiHeaders : deviceApiHeaders);
          if (body != null) req.body = jsonEncode(body);
          return await http.Response.fromStream(
            await client.send(req),
          ).timeout(const Duration(seconds: 20));
        } finally {
          client.close();
        }
      }

      final response = owner ? await send() : await withDeviceAuthRetry(send);
      checkAuthResponse(response, fallback: 'license_request_failed');
      return response.statusCode == 204
          ? <String, dynamic>{}
          : jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    }

    return owner ? withAuthRetry(run) : run();
  }

  Future<Map<String, dynamic>> mine() => request('/me');
  Future<Map<String, dynamic>> dashboard() => request('', owner: true);
  Future<Map<String, dynamic>> issue() =>
      request('/codes', owner: true, method: 'POST');
  Future<Map<String, dynamic>> approve(String id) => request(
    '/requests/${Uri.encodeComponent(id)}/approve',
    owner: true,
    method: 'POST',
  );
  Future<void> cancel(String id) async {
    await request(
      '/requests/${Uri.encodeComponent(id)}',
      owner: true,
      method: 'DELETE',
    );
  }

  Future<void> revoke(String id) async {
    await request(
      '/devices/${Uri.encodeComponent(id)}',
      owner: true,
      method: 'DELETE',
    );
  }

  Future<void> release() async {
    await request('/me', method: 'DELETE');
  }

  Future<void> rename(String id, String name) async {
    await request(
      '/devices/${Uri.encodeComponent(id)}',
      owner: true,
      method: 'PATCH',
      body: {'name': name},
    );
  }

  Future<Map<String, dynamic>> redeem(String input) async {
    final token = licenseQrToken(input);
    return request(
      '/redeem',
      method: 'POST',
      body: {
        if (token != null)
          'qrToken': token
        else
          'code': input.replaceAll(RegExp(r'[\s-]'), '').toUpperCase(),
        'name': await getDeviceName(),
        'platform': realtimePlatformName(),
      },
    );
  }
}
