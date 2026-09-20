import 'package:app/services/windows_launch_at_startup_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WindowsLaunchAtStartupService.syncWithPreferenceBestEffort', () {
    test('does not rethrow when readPreference fails', () async {
      await expectLater(
        WindowsLaunchAtStartupService.syncWithPreferenceBestEffort(
          readPreference: () async => throw StateError('prefs unavailable'),
          setSystemEnabled: (_) async {},
        ),
        completes,
      );
    });

    test('does not rethrow when setSystemEnabled fails', () async {
      await expectLater(
        WindowsLaunchAtStartupService.syncWithPreferenceBestEffort(
          readPreference: () async => true,
          setSystemEnabled: (_) async {
            throw StateError('registry missing');
          },
        ),
        completes,
      );
    });

    test('calls setSystemEnabled with stored preference', () async {
      var enabledArg = false;
      await WindowsLaunchAtStartupService.syncWithPreferenceBestEffort(
        readPreference: () async => true,
        setSystemEnabled: (enabled) async {
          enabledArg = enabled;
        },
      );
      expect(enabledArg, isTrue);
    });
  });
}
