import 'api/api.dart';
import 'device_id.dart';
import 'device_pair.dart';
import 'utils/runtime_platform.dart';

Future<void> sendDevicePairHello(String toDeviceId) async {
  final peerId = toDeviceId.trim();
  if (peerId.isEmpty) return;
  final myId = await getOrCreateDeviceId();
  if (peerId == myId) {
    throw Exception('cannot_pair_self');
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
