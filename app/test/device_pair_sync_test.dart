import 'dart:async';
import 'dart:io';
import 'package:app/services/device_pair_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'concurrent probes share one request and successful pairing is reused',
    () async {
      final sync = DevicePairSync();
      final done = Completer<void>();
      var calls = 0;
      Future<void> pair() {
        calls++;
        return done.future;
      }

      final requests = List.generate(20, (_) => sync.ensure('peer', pair));
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      done.complete();
      await Future.wait(requests);
      await sync.ensure('peer', pair);
      expect(calls, 1);
    },
  );
  test('offline failure is contained and retried after cooldown', () async {
    var now = DateTime(2026);
    final sync = DevicePairSync(now: () => now);
    var calls = 0;
    Future<void> pair() async {
      calls++;
      if (calls == 1) throw const SocketException('offline');
    }

    await sync.ensure('peer', pair);
    await sync.ensure('peer', pair);
    expect(calls, 1);
    now = now.add(const Duration(seconds: 16));
    await sync.ensure('peer', pair);
    expect(calls, 2);
  });
}
