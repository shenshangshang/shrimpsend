import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../api/api.dart';
import '../api/realtime_token.dart';
import '../logger.dart';
import 'transfer_keep_alive.dart';
import 'wukongim_jsonrpc.dart';

typedef RealtimeTokenFetcher = Future<RealtimeTokenResponse> Function({
  required String deviceId,
  required String platform,
});
typedef RealtimeMailboxFetcher = Future<List<MailboxPendingItem>> Function({
  required String deviceId,
  int afterId,
});

/// App-level WuKongIM connection. Survives ChatScreen dispose; start on login.
class RealtimeHub {
  RealtimeHub({
    RealtimeTokenFetcher? tokenFetcher,
    RealtimeMailboxFetcher? mailboxFetcher,
    Duration mailboxPollInterval = const Duration(seconds: 2),
  })  : _tokenFetcher = tokenFetcher ??
            (({required deviceId, required platform}) => getRealtimeToken(
                  deviceId: deviceId,
                  platform: platform,
                )),
        _mailboxFetcher = mailboxFetcher ?? getMailboxPending,
        _mailboxPollInterval = mailboxPollInterval;

  final RealtimeTokenFetcher _tokenFetcher;
  final RealtimeMailboxFetcher _mailboxFetcher;
  final Duration _mailboxPollInterval;

  final String presenceSessionId = const Uuid().v4();
  final StreamController<Map<String, dynamic>> _publications =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<bool> _connectedChanges =
      StreamController<bool>.broadcast();
  final List<Map<String, dynamic>> _recentPublications = [];
  final Set<String> _seenMessageIds = {};
  static const _recentLimit = 64;
  static const _seenLimit = 256;

  WukongimJsonRpcClient? _client;
  Timer? _mailboxTimer;
  Timer? _reconnectTimer;
  int _mailboxAfterId = 0;
  int _reconnectAttempt = 0;
  bool _wantConnected = false;
  bool _connecting = false;
  bool _connected = false;
  String _deviceId = '';
  String _deviceName = '';
  int _generation = 0;

  Stream<Map<String, dynamic>> get publications => _publications.stream;

  StreamSubscription<Map<String, dynamic>> listenPublications(
    void Function(Map<String, dynamic> map) onData,
  ) {
    for (final map in List<Map<String, dynamic>>.from(_recentPublications)) {
      onData(map);
    }
    return _publications.stream.listen(onData);
  }

  Stream<bool> get connectedChanges => _connectedChanges.stream;
  bool get isConnected => _connected;
  String get deviceId => _deviceId;

  Future<void> start({
    required String deviceId,
    required String deviceName,
  }) async {
    _deviceId = deviceId;
    _deviceName = deviceName;
    _wantConnected = true;
    await _connect(reason: 'start');
    _startMailboxPolling();
    unawaited(pollMailbox());
  }

  Future<void> stop() async {
    _wantConnected = false;
    _generation++;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stopMailboxPolling();
    await _tearDownClient();
    _setConnected(false);
    if (!kIsWeb && Platform.isAndroid) {
      unawaited(TransferKeepAlive.instance.disablePersistent());
    }
  }

  Future<void> onAppResumed() async {
    if (!_wantConnected) return;
    logRealtime.info('realtime hub app resumed connected=$_connected');
    await _ensureConnected(reason: 'app_resumed');
    unawaited(pollMailbox());
  }

  Future<void> onConnectivityChanged() async {
    if (!_wantConnected) return;
    logRealtime.info('realtime hub connectivity changed');
    await _ensureConnected(reason: 'connectivity', forceReconnect: true);
    unawaited(pollMailbox());
  }

  Future<void> _ensureConnected({
    required String reason,
    bool forceReconnect = false,
  }) async {
    if (_client == null) {
      await _connect(reason: reason);
      return;
    }
    if (forceReconnect || !_connected) {
      logRealtime.info('realtime hub ensureConnect reason=$reason connected=$_connected');
      await _tearDownClient();
      if (_wantConnected) {
        await _connect(reason: reason);
      }
    }
  }

  Future<void> _connect({required String reason}) async {
    if (!_wantConnected || _connecting) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _connecting = true;
    final gen = ++_generation;
    logRealtime.info('realtime hub connect reason=$reason');
    try {
      final tokens = await _tokenFetcher(
        deviceId: _deviceId,
        platform: realtimePlatformName(),
      );
      if (!_wantConnected || gen != _generation) return;
      await _tearDownClient();
      final client = WukongimJsonRpcClient(
        websocketUrl: tokens.websocketUrl,
        uid: tokens.uid,
        token: tokens.token,
        deviceId: _deviceId,
        deviceFlag: tokens.deviceFlag,
        onMessage: (params) {
          final id = params['messageId']?.toString();
          if (id != null && id.isNotEmpty) {
            if (_seenMessageIds.contains(id)) return;
            _seenMessageIds.add(id);
            if (_seenMessageIds.length > _seenLimit) {
              _seenMessageIds.remove(_seenMessageIds.first);
            }
          }
          final envelope = unwrapWukongimParams(params);
          if (envelope != null) {
            dispatchRaw(envelope);
          }
        },
        onConnected: () {
          logRealtime.info('realtime hub connected');
          _reconnectTimer?.cancel();
          _reconnectTimer = null;
          _reconnectAttempt = 0;
          _setConnected(true);
          if (!kIsWeb && Platform.isAndroid) {
            unawaited(TransferKeepAlive.instance.enablePersistent());
          }
        },
        onDisconnected: (why) {
          logRealtime.info('realtime hub disconnected: $why');
          _setConnected(false);
          if (_wantConnected) {
            _startMailboxPolling();
            _scheduleReconnect();
          }
        },
      );
      _client = client;
      await client.connect(timeout: const Duration(seconds: 20));
      if (!_wantConnected || gen != _generation) return;
      logRealtime.info(
        'realtime hub connecting uid=${tokens.uid} ws=${tokens.websocketUrl} name=$_deviceName',
      );
    } catch (e, st) {
      logRealtime.warning('realtime hub connect failed: $e\n$st');
      _setConnected(false);
      if (_wantConnected && gen == _generation) {
        _scheduleReconnect();
      }
    } finally {
      _connecting = false;
    }
  }

  void _scheduleReconnect() {
    if (!_wantConnected) return;
    _reconnectTimer?.cancel();
    final exp = math.min(_reconnectAttempt, 4);
    final delayMs = math.min(8000, 500 * (1 << exp));
    _reconnectAttempt++;
    logRealtime.info('realtime hub reconnect in ${delayMs}ms');
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      if (_wantConnected) {
        unawaited(_connect(reason: 'reconnect'));
      }
    });
  }

  Future<void> pollMailbox() async {
    if (!_wantConnected || _deviceId.isEmpty) return;
    try {
      final items = await _mailboxFetcher(
        deviceId: _deviceId,
        afterId: _mailboxAfterId,
      );
      await ingestMailbox(items);
    } catch (e) {
      logRealtime.warning('realtime hub mailbox poll failed: $e');
    }
  }

  @visibleForTesting
  Future<void> ingestMailbox(List<MailboxPendingItem> items) async {
    for (final item in items) {
      if (item.id > _mailboxAfterId) {
        _mailboxAfterId = item.id;
      }
      if (item.data.isEmpty) continue;
      dispatchRaw(item.data);
    }
  }

  @visibleForTesting
  void dispatchRaw(Map<String, dynamic> map) {
    if (_publications.isClosed) return;
    _recentPublications.add(map);
    if (_recentPublications.length > _recentLimit) {
      _recentPublications.removeAt(0);
    }
    _publications.add(map);
  }

  void _startMailboxPolling() {
    _mailboxTimer ??= Timer.periodic(_mailboxPollInterval, (_) {
      if (_wantConnected && !_connected) {
        unawaited(pollMailbox());
      }
    });
  }

  void _stopMailboxPolling() {
    _mailboxTimer?.cancel();
    _mailboxTimer = null;
  }

  void _setConnected(bool value) {
    if (_connected == value) return;
    _connected = value;
    if (!_connectedChanges.isClosed) {
      _connectedChanges.add(value);
    }
  }

  Future<void> _tearDownClient() async {
    final client = _client;
    _client = null;
    if (client != null) {
      try {
        await client.disconnect();
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    await stop();
    await _publications.close();
    await _connectedChanges.close();
  }
}
