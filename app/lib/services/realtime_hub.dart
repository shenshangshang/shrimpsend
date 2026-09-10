import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:centrifuge/centrifuge.dart' as centrifuge;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../api/api.dart';
import '../config/env.dart';
import '../logger.dart';
import 'transfer_keep_alive.dart';

typedef RealtimeTokenFetcher = Future<CentrifugoTokenResponse> Function();
typedef RealtimeMailboxFetcher = Future<List<MailboxPendingItem>> Function({
  required String deviceId,
  int afterId,
});
typedef RealtimeClientFactory = centrifuge.Client Function(
  String url,
  centrifuge.ClientConfig config,
);

/// App-level Centrifugo connection. Survives ChatScreen dispose; start on login.
class RealtimeHub {
  RealtimeHub({
    RealtimeTokenFetcher? tokenFetcher,
    RealtimeMailboxFetcher? mailboxFetcher,
    RealtimeClientFactory? clientFactory,
    Duration mailboxPollInterval = const Duration(seconds: 2),
  })  : _tokenFetcher = tokenFetcher ?? getCentrifugoToken,
        _mailboxFetcher = mailboxFetcher ?? getMailboxPending,
        _clientFactory = clientFactory ?? centrifuge.createClient,
        _mailboxPollInterval = mailboxPollInterval;

  final RealtimeTokenFetcher _tokenFetcher;
  final RealtimeMailboxFetcher _mailboxFetcher;
  final RealtimeClientFactory _clientFactory;
  final Duration _mailboxPollInterval;

  final String presenceSessionId = const Uuid().v4();
  final StreamController<Map<String, dynamic>> _publications =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<bool> _connectedChanges =
      StreamController<bool>.broadcast();
  final List<Map<String, dynamic>> _recentPublications = [];
  static const _recentLimit = 64;

  centrifuge.Client? _client;
  StreamSubscription<centrifuge.PublicationEvent>? _publicationSub;
  StreamSubscription<centrifuge.ConnectedEvent>? _connectedSub;
  StreamSubscription<centrifuge.DisconnectedEvent>? _disconnectedSub;
  Timer? _mailboxTimer;
  int _mailboxAfterId = 0;
  bool _wantConnected = false;
  bool _connecting = false;
  bool _connected = false;
  String _deviceId = '';
  String _deviceName = '';
  int _generation = 0;

  Stream<Map<String, dynamic>> get publications => _publications.stream;

  /// Late subscribers receive the recent buffer (mailbox may arrive before ChatScreen).
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
    _stopMailboxPolling();
    await _tearDownClient();
    _setConnected(false);
    if (Platform.isAndroid) {
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
    final client = _client;
    if (client == null) {
      await _connect(reason: reason);
      return;
    }
    if (forceReconnect || client.state != centrifuge.State.connected) {
      logRealtime.info(
        'realtime hub ensureConnect reason=$reason state=${client.state} force=$forceReconnect',
      );
      if (forceReconnect && client.state == centrifuge.State.connected) {
        await client.disconnect();
      }
      if (_wantConnected) {
        await client.connect();
      }
    }
  }

  Future<void> _connect({required String reason}) async {
    if (!_wantConnected || _connecting) return;
    _connecting = true;
    final gen = ++_generation;
    logRealtime.info('realtime hub connect reason=$reason ws=${Env.centrifugoWs}');
    try {
      final tokens = await _tokenFetcher();
      if (!_wantConnected || gen != _generation) return;
      await _tearDownClient();
      final identity = utf8.encode(
        jsonEncode({
          'deviceId': _deviceId,
          'name': _deviceName,
          'platform': Platform.operatingSystem,
          'sessionId': presenceSessionId,
        }),
      );
      final client = _clientFactory(
        Env.centrifugoWs,
        centrifuge.ClientConfig(
          token: tokens.connectionToken,
          data: identity,
          getData: () async => identity,
          minReconnectDelay: const Duration(milliseconds: 200),
          maxReconnectDelay: const Duration(seconds: 8),
          timeout: const Duration(seconds: 8),
          getToken: (_) async {
            final r = await _tokenFetcher();
            return r.connectionToken;
          },
        ),
      );
      _connectedSub = client.connected.listen((_) {
        logRealtime.info('realtime hub connected');
        _setConnected(true);
        if (Platform.isAndroid) {
          unawaited(TransferKeepAlive.instance.enablePersistent());
        }
        unawaited(pollMailbox());
      });
      _disconnectedSub = client.disconnected.listen((e) {
        logRealtime.info('realtime hub disconnected: ${e.reason}');
        _setConnected(false);
        if (_wantConnected) {
          _startMailboxPolling();
        }
      });
      final sub = client.newSubscription(
        tokens.channel,
        centrifuge.SubscriptionConfig(
          token: tokens.subscriptionToken,
          getToken: (_) async {
            final r = await _tokenFetcher();
            return r.subscriptionToken;
          },
        ),
      );
      _publicationSub = sub.publication.listen((e) {
        _emitRaw(e.data);
      });
      sub.subscribe();
      _client = client;
      await client.connect();
      logRealtime.info('realtime hub subscribed channel=${tokens.channel}');
    } catch (e, st) {
      logRealtime.warning('realtime hub connect failed: $e\n$st');
      _setConnected(false);
    } finally {
      _connecting = false;
    }
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

  void _emitRaw(List<int> raw) {
    if (raw.isEmpty) return;
    try {
      final map = jsonDecode(utf8.decode(Uint8List.fromList(raw)))
          as Map<String, dynamic>;
      dispatchRaw(map);
    } catch (e, st) {
      logRealtime.warning('realtime hub publication decode failed: $e\n$st');
    }
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
    await _publicationSub?.cancel();
    await _connectedSub?.cancel();
    await _disconnectedSub?.cancel();
    _publicationSub = null;
    _connectedSub = null;
    _disconnectedSub = null;
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
