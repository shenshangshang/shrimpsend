import 'dart:async';
import 'dart:io';
import 'package:app/lan/lan_receiver.dart';
import 'package:app/services/file_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'concurrent starts coalesce and a stopped start cannot resurrect the receiver',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final temp = await Directory.systemTemp.createTemp('lan-lifecycle-');
      addTearDown(() => temp.delete(recursive: true));
      SharedPreferences.setMockInitialValues({
        'ultrasend_custom_save_dir': temp.path,
      });
      FileStore.invalidateReceiveDirCache();
      addTearDown(FileStore.invalidateReceiveDirCache);
      final ipPending = Completer<String>();
      final ipRequested = Completer<void>();
      const channel = MethodChannel('dev.fluttercommunity.plus/network_info');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (!ipRequested.isCompleted) ipRequested.complete();
            return ipPending.future;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      var registrations = 0;
      final receiver = LanReceiver(
        deviceId: 'test-lifecycle',
        onFileReceived:
            (_, __, ___, {messageId, senderLocalId, lastModifiedMs}) {},
        onRegisterLanHttpUrl: (_) async {
          registrations++;
        },
      );
      addTearDown(receiver.stop);
      final first = receiver.start();
      final second = receiver.start();
      expect(identical(first, second), isTrue);
      await ipRequested.future.timeout(const Duration(seconds: 2));
      await receiver.stop();
      ipPending.complete('192.0.2.1');
      expect(await first, isNull);
      expect(await second, isNull);
      expect(receiver.isActive, isFalse);
      expect(registrations, 0);
    },
  );
}
