import 'api/api.dart';
import 'api/client.dart';
import 'device_id.dart';
import 'device_pair.dart';
import 'utils/runtime_platform.dart';

Future<void> ensureDeviceAccessToken() async {
  if (hasDeviceAccessToken) return;
  final id = await getOrCreateDeviceId();
  await createDeviceSession(deviceId: id, platform: realtimePlatformName());
}

Future<void> sendDevicePairHello(String toDeviceId) async {
  final peerId = normalizePeerDeviceId(toDeviceId);
  if (peerId == null || peerId.isEmpty) {
    throw Exception('pair_invalid');
  }
  final myId = await getOrCreateDeviceId();
  if (peerId == myId) {
    throw Exception('cannot_pair_self');
  }
  await ensureDeviceAccessToken();
  if (!hasDeviceAccessToken) {
    throw Exception('device_session_unavailable');
  }
  final name = await getDeviceName();
  await pairDevice(peerId);
  await sendMessage({
    'type': 'device_pair_hello',
    'toDeviceId': peerId,
    'fromDeviceId': myId,
    'ts': DateTime.now().millisecondsSinceEpoch,
    'payload': {
      'deviceId': myId,
      'name': name,
      'platform': RuntimePlatform.osName,
    },
  });
}

DeviceDto deviceDtoFromPairHello({
  required String deviceId,
  String? name,
  String? platform,
}) {
  final id = deviceId.trim();
  return DeviceDto(
    deviceId: id,
    name: (name != null && name.trim().isNotEmpty)
        ? name.trim()
        : shortDeviceLabel(id),
    platform: platform,
    presenceStatus: 'online',
  );
}
