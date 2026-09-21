import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../logger.dart';

typedef WukongimMessageHandler = void Function(Map<String, dynamic> params);

/// WuKongIM JSON-RPC 2.0 WebSocket client (connect + recv + ping).
class WukongimJsonRpcClient {
  WukongimJsonRpcClient({
    required this.websocketUrl,
    required this.uid,
    required this.token,
    required this.deviceId,
    required this.deviceFlag,
    required this.onMessage,
    this.onConnected,
    this.onDisconnected,
  });

  final String websocketUrl;
  final String uid;
  final String token;
  final String deviceId;
  final int deviceFlag;
  final WukongimMessageHandler onMessage;
  final void Function()? onConnected;
  final void Function(String reason)? onDisconnected;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _pingTimer;
  Completer<void>? _connectDone;
  String? _connectId;
  String? _pendingPingId;
  var _id = 0;
  var _closed = false;

  Future<void> connect({Duration timeout = const Duration(seconds: 20)}) async {
    _closed = false;
    _pendingPingId = null;
    final done = Completer<void>();
    _connectDone = done;
    final channel = WebSocketChannel.connect(Uri.parse(websocketUrl));
    _channel = channel;
    _sub = channel.stream.listen(
      _onFrame,
      onError: (Object e) {
        logRealtime.warning('wukongim ws error: $e');
        if (!done.isCompleted) {
          done.completeError(e);
        }
        _handleDisconnect('error');
      },
      onDone: () {
        if (!done.isCompleted) {
          done.completeError(
            StateError('wukongim socket closed before connect'),
          );
        }
        _handleDisconnect('done');
      },
    );
    _connectId = _nextId();
    _send({
      'method': 'connect',
      'id': _connectId,
      'params': {
        'uid': uid,
        'token': token,
        'deviceId': deviceId,
        'deviceFlag': deviceFlag,
        'clientTimestamp': DateTime.now().millisecondsSinceEpoch,
      },
    });
    try {
      await done.future.timeout(timeout);
    } on TimeoutException {
      _connectDone = null;
      await disconnect();
      throw TimeoutException('wukongim connect timeout');
    }
  }

  Future<void> disconnect() async {
    _closed = true;
    _pingTimer?.cancel();
    _pingTimer = null;
    await _sub?.cancel();
    _sub = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    final pending = _connectDone;
    _connectDone = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(StateError('wukongim disconnected'));
    }
  }

  void _onFrame(dynamic raw) {
    try {
      final text = raw is String
          ? raw
          : utf8.decode(
              raw is Uint8List
                  ? raw
                  : Uint8List.fromList(List<int>.from(raw as List)),
            );
      final msg = jsonDecode(text);
      if (msg is! Map) return;
      final map = Map<String, dynamic>.from(msg);
      if (map['error'] != null && map['id'] != null) {
        logRealtime.warning('wukongim rpc error: ${map['error']}');
        final pending = _connectDone;
        if (pending != null &&
            !pending.isCompleted &&
            map['id'] == _connectId) {
          pending.completeError(StateError('wukongim auth: ${map['error']}'));
        }
        return;
      }
      if (map['id'] != null && map['id'] == _pendingPingId) {
        _pendingPingId = null;
        return;
      }
      if (map['id'] == _connectId && map['result'] != null && !_closed) {
        _startPing();
        final pending = _connectDone;
        if (pending != null && !pending.isCompleted) {
          pending.complete();
        }
        onConnected?.call();
        return;
      }
      if (map['method'] == 'recv' || map['method'] == 'message') {
        if (map['params'] is Map) {
          final params = Map<String, dynamic>.from(map['params'] as Map);
          if (params['messageId'] != null) {
            _send({
              'method': 'recvack',
              'params': {
                'messageId': params['messageId'].toString(),
                'messageSeq': params['messageSeq'],
              },
            });
          }
          onMessage(params);
        }
      }
    } catch (e, st) {
      logRealtime.warning('wukongim frame parse failed: $e\n$st');
    }
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_pendingPingId != null) {
        _channel?.sink.close();
        _handleDisconnect('heartbeat timeout');
        return;
      }
      _pendingPingId = _nextId();
      _send({'method': 'ping', 'id': _pendingPingId});
    });
  }

  void _send(Map<String, dynamic> body) {
    final channel = _channel;
    if (channel == null) return;
    channel.sink.add(jsonEncode(body));
  }

  String _nextId() => 'r-${++_id}';

  void _handleDisconnect(String reason) {
    _pingTimer?.cancel();
    _pingTimer = null;
    if (!_closed) {
      onDisconnected?.call(reason);
    }
  }
}

Map<String, dynamic>? unwrapWukongimParams(Map<String, dynamic> params) {
  final payload = params['payload'];
  if (payload == null) return null;
  Object decoded = payload;
  if (payload is String) {
    try {
      if (payload.isNotEmpty &&
          (payload.startsWith('{') || payload.startsWith('['))) {
        decoded = jsonDecode(payload);
      } else {
        decoded = jsonDecode(utf8.decode(base64Decode(payload)));
      }
    } catch (_) {
      return null;
    }
  }
  if (decoded is! Map) return null;
  final map = Map<String, dynamic>.from(decoded);
  final type = map['type'];
  if (type is num && type.toInt() == 200 && map['envelope'] is Map) {
    return Map<String, dynamic>.from(map['envelope'] as Map);
  }
  if (type is String) {
    return map;
  }
  return null;
}
