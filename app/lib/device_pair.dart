const kDevicePairUriPrefix = 'ultrasend://pair/';

String devicePairUri(String deviceId) => '$kDevicePairUriPrefix$deviceId';

String? parseDevicePairUri(String text) {
  final trimmed = text.trim();
  if (!trimmed.toLowerCase().startsWith(kDevicePairUriPrefix)) return null;
  final rest = trimmed.substring(kDevicePairUriPrefix.length).trim();
  final id = rest.split(RegExp(r'[?#]')).first.trim();
  return id.isEmpty ? null : id;
}

String shortDeviceLabel(String deviceId) {
  if (deviceId.length <= 12) return deviceId;
  return '${deviceId.substring(0, 8)}…';
}
