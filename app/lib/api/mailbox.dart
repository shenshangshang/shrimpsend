import 'dart:convert';
import 'package:http/http.dart' as http;
import '../logger.dart';
import 'client.dart';

class MailboxPendingItem {
  final int id;
  final Map<String, dynamic> data;

  MailboxPendingItem({required this.id, required this.data});

  factory MailboxPendingItem.fromJson(Map<String, dynamic> j) {
    final idVal = j['id'];
    final id = idVal is num
        ? idVal.toInt()
        : int.tryParse(idVal?.toString() ?? '') ?? 0;
    final raw = j['data'];
    final data = raw is Map<String, dynamic>
        ? raw
        : (raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{});
    return MailboxPendingItem(id: id, data: data);
  }
}

Future<List<MailboxPendingItem>> getMailboxPending({
  required String deviceId,
  int afterId = 0,
}) async {
  logApi.info('getMailboxPending deviceId=$deviceId afterId=$afterId');
  Future<List<MailboxPendingItem>> fetch() async {
    final uri = Uri.parse('$apiBaseUrl/api/mailbox/pending').replace(
      queryParameters: {
        'deviceId': deviceId,
        if (afterId > 0) 'afterId': afterId.toString(),
      },
    );
    final r = await http.get(uri, headers: realtimeApiHeaders);
    if (!hasAccessToken) {
      if (r.statusCode < 200 || r.statusCode >= 300) {
        throw Exception(errorMessageFromResponse(r, '加载待收信令失败'));
      }
    } else {
      checkAuthResponse(r, fallback: '加载待收信令失败');
    }
    final list = (jsonDecode(r.body) as List)
        .map((e) => MailboxPendingItem.fromJson(e as Map<String, dynamic>))
        .toList();
    logApi.info('getMailboxPending success count=${list.length}');
    return list;
  }

  if (hasAccessToken) {
    return withAuthRetry(fetch);
  }
  return fetch();
}
