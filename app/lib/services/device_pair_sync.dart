import 'dart:async';

/// Background discovery may request the same pairing from several probes.
/// Coalesce those requests and back off when the server is unavailable.
class DevicePairSync {
  DevicePairSync({DateTime Function()? now}) : _now = now ?? DateTime.now;
  final DateTime Function() _now;
  final _pending = <String, Future<void>>{};
  final _nextAttempt = <String, DateTime>{};

  Future<void> ensure(String key, Future<void> Function() pair) {
    final pending = _pending[key];
    if (pending != null) return pending;
    if (_now().isBefore(_nextAttempt[key] ?? DateTime(1970))) {
      return Future.value();
    }
    final future = Future<void>(() async {
      var delay = const Duration(seconds: 15);
      try {
        await pair();
        delay = const Duration(minutes: 1);
      } catch (_) {
        // Offline LAN discovery remains useful; the next probe retries sync.
      } finally {
        _pending.remove(key);
        if (_nextAttempt.length >= 256)
          _nextAttempt.remove(_nextAttempt.keys.first);
        _nextAttempt[key] = _now().add(delay);
      }
    });
    _pending[key] = future;
    return future;
  }
}
