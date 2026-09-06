import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:network_info_plus/network_info_plus.dart';

import '../logger.dart';
import '../services/cancel_token.dart';
import '../services/file_store.dart';
import 'lan_url.dart';
import 'transfer_worker.dart';

typedef OnLanMessageReceived = void Function(
  String text,
  String fromDeviceId,
  String? fromDeviceName,
);

final _log = logChat;

/// Manages HTTP server(s) via Isolate pool for LAN file transfers.
///
/// - Direct push: remote client POSTs to /transfer
/// - Reverse pull: remote client GETs from /download?offerId=xxx
/// - Probe: remote client GETs /probe
class LanReceiver {
  LanReceiver({
    required this.deviceId,
    required this.onFileReceived,
    required Future<void> Function(String lanHttpUrl) onRegisterLanHttpUrl,
    this.onReceiveProgress,
    this.onReceiveError,
    this.onMessageReceived,
    this.onPeerRegistered,
    this.deviceName,
    this.platform,
  }) : _onRegisterLanHttpUrl = onRegisterLanHttpUrl;

  final String deviceId;
  final String? deviceName;
  final String? platform;
  final OnLanFileReceived onFileReceived;
  final OnLanReceiveProgress? onReceiveProgress;
  final OnLanReceiveError? onReceiveError;
  final OnLanMessageReceived? onMessageReceived;
  final OnPeerRegistered? onPeerRegistered;
  final Future<void> Function(String lanHttpUrl) _onRegisterLanHttpUrl;

  HttpTransferServer? _httpServer;
  String? _lanHttpUrl;
  String? _tempDirPath;
  // The transfer port is OS-assigned (bind port 0); peers get it from the
  // announced URL, so there is no fixed port range to exhaust.
  /// Fewer workers reduces concurrent partial writes on the receiver cache.
  static const int _workerCount = 2;
  static const Duration _pullExpiry = Duration(minutes: 5);

  bool get isActive => _lanHttpUrl != null;
  String? get lanHttpUrl => _lanHttpUrl;

  /// Registers a file for reverse pull transfer.
  /// Returns (pullUrl, future) where pullUrl is HTTP URL for the receiver to GET.
  (String?, Future<bool>?) offerFileForPull(
    String offerId,
    String fileName,
    int size, {
    String? filePath,
    List<int>? bytes,
    CancelToken? cancelToken,
    VoidCallback? onPullStarted,
    OnPullSendProgress? onSendProgress,
    VoidCallback? onPullCompleted,
  }) {
    if (_lanHttpUrl == null || _httpServer == null) return (null, null);
    final completer = Completer<bool>();
    _httpServer!.registerPullFile(
      offerId,
      fileName,
      size,
      filePath: filePath,
      bytes: bytes != null
          ? (bytes is Uint8List ? bytes : Uint8List.fromList(bytes))
          : null,
      onPullStarted: onPullStarted,
      onSendProgress: onSendProgress,
      onPullCompleted: onPullCompleted,
      completer: completer,
    );
    cancelToken?.onCancel(() {
      _httpServer?.unregisterPullFile(offerId);
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    });
    Future.delayed(_pullExpiry, () {
      _httpServer?.unregisterPullFile(offerId);
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    });
    final pullUrl =
        '$_lanHttpUrl/download?offerId=${Uri.encodeComponent(offerId)}';
    _log.info('LanReceiver offerFileForPull offerId=$offerId pullUrl=$pullUrl');
    return (pullUrl, completer.future);
  }

  /// Picks a LAN IPv4 address: prefer the actual IPv4 egress address (a real
  /// working NIC), then WiFi IP, then first non-loopback from
  /// NetworkInterface.list. Multi-NIC machines often carry stale static IPs on
  /// a disconnected adapter — announcing that address makes every peer probe
  /// fail, so the egress probe must win over plain enumeration.
  static Future<String?> _getLanIp() async {
    try {
      final sock = await Socket.connect(
        InternetAddress('223.5.5.5'),
        53,
        timeout: const Duration(seconds: 2),
      );
      final local = sock.address.address;
      sock.destroy();
      if (_isPrivateIpv4(local)) return local;
    } catch (e) {
      _log.info('LanReceiver egress probe failed: $e');
    }
    try {
      final info = NetworkInfo();
      final wifiIp = await info.getWifiIP();
      if (wifiIp != null && wifiIp.isNotEmpty && wifiIp != '127.0.0.1') {
        return wifiIp;
      }
    } catch (e) {
      _log.warning('LanReceiver getWifiIP failed: $e');
    }
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      String? privateFirst;
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.isLoopback) continue;
          final a = addr.address;
          if (_isPrivateIpv4(a)) {
            return a;
          }
          privateFirst ??= a;
        }
      }
      return privateFirst;
    } catch (e) {
      _log.warning('LanReceiver NetworkInterface.list failed: $e');
    }
    return null;
  }

  static bool _isPrivateIpv4(String a) {
    if (a.startsWith('10.')) return true;
    if (a.startsWith('192.168.')) return true;
    if (a.startsWith('172.')) {
      final second = int.tryParse(a.split('.')[1]);
      if (second != null && second >= 16 && second <= 31) return true;
    }
    return false;
  }

  /// Starts the HTTP transfer server on an OS-assigned ephemeral port, gets
  /// the LAN IP, and registers the lanHttpUrl. The port is never hardcoded:
  /// peers learn it from the announced URL (server signalling / mDNS), so a
  /// fixed range would only ever collide with other local services.
  Future<String?> start() async {
    if (_httpServer != null) return _lanHttpUrl;

    _tempDirPath ??= await FileStore.getReceiveDir();
    final lanIp = await _getLanIp();
    if (lanIp == null || lanIp.isEmpty) {
      _log.warning('LanReceiver no usable LAN IP');
      return null;
    }
    _log.info('LanReceiver start lanIp=$lanIp');

    HttpTransferServer? tentative;
    try {
      tentative = HttpTransferServer(
        onFileReceived: onFileReceived,
        onReceiveProgress: onReceiveProgress,
        onReceiveError: onReceiveError,
        onMessageReceived: onMessageReceived,
        onPeerRegistered: onPeerRegistered,
      );
      // Bind to anyIPv4 port 0 so a stale/wrong interface guess or an
      // occupied port can never silently kill the receiver; the announced
      // URL still uses the picked LAN IP and the actual bound port.
      await tentative
          .start(
            InternetAddress.anyIPv4.address,
            0,
            _workerCount,
            _tempDirPath!,
            deviceId: deviceId,
            deviceName: deviceName,
            platform: platform,
            announceAddress: lanIp,
          )
          .timeout(const Duration(seconds: 8));
      final url = tentative.lanHttpUrl!;
      _log.info('LanReceiver serving at $url');
      await _onRegisterLanHttpUrl(url);
      _httpServer = tentative;
      _lanHttpUrl = url;
      return _lanHttpUrl;
    } catch (e) {
      await tentative?.stop();
      _log.warning('LanReceiver start failed: $e');
      return null;
    }
  }

  /// Cancel an ongoing receive for the given [fileName]. Pass [fileId] when
  /// available so concurrent transfers sharing the same display name are not
  /// torn down together.
  void cancelReceive(String fileName, {String? fileId}) {
    _httpServer?.cancelReceive(fileName, fileId: fileId);
  }

  Future<void> stop() async {
    await _httpServer?.stop();
    _httpServer = null;
    _lanHttpUrl = null;
    _tempDirPath = null;
    _log.info('LanReceiver stopped');
  }
}
