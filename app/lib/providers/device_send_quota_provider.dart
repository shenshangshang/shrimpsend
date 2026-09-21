import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../api/client.dart';
import '../api/device_send_quota.dart';
import '../logger.dart';

class DeviceSendQuotaNotifier extends Notifier<DeviceSendQuota?> {
  int _hitSeq = 0;
  bool dialogOpen = false;

  @override
  DeviceSendQuota? build() {
    onDeviceSendQuotaUpdate = (quota) {
      if (quota.limited) {
        _hitSeq += 1;
        state = quota.copyWith(hitSeq: _hitSeq);
      } else {
        state = quota.copyWith(hitSeq: state?.hitSeq ?? 0, limited: false);
      }
    };
    ref.onDispose(() {
      onDeviceSendQuotaUpdate = null;
    });
    return null;
  }

  Future<void> refresh() async {
    if (!hasDeviceAccessToken) return;
    try {
      final r = await withDeviceAuthRetry(
        () => http.get(
          Uri.parse('$apiBaseUrl/api/messages/device-quota'),
          headers: deviceApiHeaders,
        ),
      );
      if (r.statusCode != 200) return;
      final quota = parseDeviceSendQuota(headers: r.headers, body: r.body);
      if (quota != null) {
        state = quota.copyWith(hitSeq: state?.hitSeq ?? 0, limited: false);
      }
    } catch (e) {
      logApi.fine('device-quota refresh failed: $e');
    }
  }
}

final deviceSendQuotaProvider =
    NotifierProvider<DeviceSendQuotaNotifier, DeviceSendQuota?>(
      DeviceSendQuotaNotifier.new,
    );
