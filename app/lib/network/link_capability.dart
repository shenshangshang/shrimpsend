/// 规范化平台字符串（与 [DeviceDto.platform] 一致）。
/// HarmonyOS Flutter embedding reports `ohos`; persist/compare as `harmonyos`.
String normalizeOs(String? raw) {
  if (raw == null || raw.isEmpty) return 'unknown';
  final o = raw.toLowerCase();
  if (o == 'ohos' || o == 'harmony' || o == 'harmonyos') return 'harmonyos';
  return o;
}
