/// Send-time transfer hops, ordered by expected speed.
///
/// This is a priori ranking plus connectivity attempts — not a bandwidth race.
enum TransferHop {
  /// Sender POSTs to the receiver's LAN HTTP server.
  httpPush,

  /// Receiver GETs from the sender's LAN HTTP server (`lan_file_offer`).
  httpPull,

  /// WebRTC DataChannel.
  webrtc,

  /// S3-compatible relay. Logged-in only.
  s3,
}

/// Runtime UI phase while the send cascade probes and then transfers.
abstract final class TransferPhase {
  static const tryingHttp = 'tryingHttp';
  static const waitingPull = 'waitingPull';
  static const connectingWebrtc = 'connectingWebrtc';
  static const connectingWebrtcFallback = 'connectingWebrtcFallback';
  static const tryingS3 = 'tryingS3';
  static const tryingS3Fallback = 'tryingS3Fallback';
  static const sendingHttp = 'sendingHttp';
  static const sendingWebrtc = 'sendingWebrtc';
  static const sendingS3 = 'sendingS3';

  static bool isConnecting(String? phase) {
    return phase == tryingHttp ||
        phase == waitingPull ||
        phase == connectingWebrtc ||
        phase == connectingWebrtcFallback ||
        phase == tryingS3 ||
        phase == tryingS3Fallback;
  }

  static String? channelOf(String? phase) {
    return switch (phase) {
      tryingHttp || waitingPull || sendingHttp => 'lan',
      connectingWebrtc ||
      connectingWebrtcFallback ||
      sendingWebrtc => 'webrtc',
      tryingS3 || tryingS3Fallback || sendingS3 => 's3',
      _ => null,
    };
  }
}

class TransferPathInput {
  const TransferPathInput({
    required this.localIsWeb,
    required this.peerIsWeb,
    required this.isLoggedIn,
    required this.webrtcAvailable,
    required this.s3Configured,
    required this.s3Online,
    this.isS3VirtualSession = false,
  });

  /// Browser clients cannot serve LAN HTTP (no reverse-pull, cannot receive push).
  final bool localIsWeb;
  final bool peerIsWeb;
  final bool isLoggedIn;
  final bool webrtcAvailable;
  final bool s3Configured;
  final bool s3Online;
  final bool isS3VirtualSession;
}

/// Whether this device should act on a `lan_file_offer`.
///
/// Directed envelopes (`toDeviceId`) win so guest `device-send` and
/// logged-in 1:1 signaling reach the intended peer. Broadcast offers still
/// match [targetDeviceIds].
bool isLanFileOfferForMe({
  required String me,
  String? toDeviceId,
  Object? targetDeviceIds,
}) {
  if (toDeviceId != null && toDeviceId.isNotEmpty) {
    return toDeviceId == me;
  }
  if (targetDeviceIds is List) {
    return targetDeviceIds.contains(me);
  }
  return false;
}

/// Hops that can be attempted for this pair, fastest first.
///
/// Direction rules:
/// - Web → App: [TransferHop.httpPush] only (no pull)
/// - App → Web: [TransferHop.httpPull] only (no push)
/// - Web → Web: skip HTTP
/// - Guest: same HTTP direction; S3 omitted
List<TransferHop> applicableTransferHops(TransferPathInput input) {
  if (input.isS3VirtualSession) {
    if (input.isLoggedIn && input.s3Configured && input.s3Online) {
      return const [TransferHop.s3];
    }
    return const [];
  }

  final hops = <TransferHop>[];

  // Web has no LAN HTTP server, so it cannot receive POST /transfer.
  if (!input.peerIsWeb) {
    hops.add(TransferHop.httpPush);
  }
  // Web cannot expose files for reverse pull.
  if (!input.localIsWeb) {
    hops.add(TransferHop.httpPull);
  }

  if (input.webrtcAvailable) {
    hops.add(TransferHop.webrtc);
  }

  if (input.isLoggedIn && input.s3Configured && input.s3Online) {
    hops.add(TransferHop.s3);
  }

  return hops;
}

bool hopsIncludeHttp(List<TransferHop> hops) {
  return hops.contains(TransferHop.httpPush) ||
      hops.contains(TransferHop.httpPull);
}

/// Short-TTL skip of hops that just failed so the next send does not stall
/// on a path that is known-down. Unknown / expired → try.
class TransferHopSkipCache {
  TransferHopSkipCache({this.ttl = const Duration(seconds: 20)});

  final Duration ttl;
  final Map<String, Map<TransferHop, DateTime>> _failedAt = {};

  void markFailed(String peerId, TransferHop hop) {
    _failedAt.putIfAbsent(peerId, () => {})[hop] = DateTime.now();
  }

  void markSucceeded(String peerId, TransferHop hop) {
    _failedAt[peerId]?.remove(hop);
  }

  bool shouldSkip(String peerId, TransferHop hop) {
    final at = _failedAt[peerId]?[hop];
    if (at == null) return false;
    if (DateTime.now().difference(at) > ttl) {
      _failedAt[peerId]?.remove(hop);
      return false;
    }
    return true;
  }

  List<TransferHop> filter(String peerId, List<TransferHop> hops) {
    return hops.where((hop) => !shouldSkip(peerId, hop)).toList(growable: false);
  }
}
