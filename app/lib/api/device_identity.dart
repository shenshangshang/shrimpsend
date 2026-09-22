import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../device_id.dart';
import 'client.dart';
import 'devices.dart';

int _presenceSequence = 0;
Future<DeviceDto> publishDevicePresence({
  required String sessionId,
  required String status,
  required String platform,
  String? lanHttpUrl,
}) async {
  final sequence = ++_presenceSequence;
  final name = await getDeviceName();
  final response = await withDeviceAuthRetry(
    () => http
        .post(
          Uri.parse('$apiBaseUrl/api/devices/self/presence'),
          headers: deviceApiHeaders,
          body: jsonEncode({
            'sessionId': sessionId,
            'sequence': sequence,
            'status': status,
            'platform': platform,
            'name': name.length > 80 ? name.substring(0, 80) : name,
            'lanHttpUrl': lanHttpUrl,
          }),
        )
        .timeout(const Duration(seconds: 8)),
  );
  if (response.statusCode != 200)
    throw Exception('Device presence unavailable');
  if (status == 'online') await syncDeviceName();
  return DeviceDto.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
}

Future<void> syncDeviceName() async {
  final prefs = await SharedPreferences.getInstance();
  final name = prefs.getString(pendingDeviceNameKey);
  if (name == null) return;
  final response = await withDeviceAuthRetry(
    () => http
        .patch(
          Uri.parse('$apiBaseUrl/api/devices/self/profile'),
          headers: deviceApiHeaders,
          body: jsonEncode({'name': name}),
        )
        .timeout(const Duration(seconds: 8)),
  );
  if (response.statusCode != 200)
    throw Exception('Device name sync unavailable');
  if (prefs.getString(pendingDeviceNameKey) == name)
    await prefs.remove(pendingDeviceNameKey);
}
