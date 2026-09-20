import 'package:app/services/boot_best_effort.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('bestEffortBootStep', () {
    test('does not rethrow when step fails', () async {
      await expectLater(
        bestEffortBootStep('test step', () async {
          throw StateError('non-fatal init failed');
        }),
        completes,
      );
    });

    test('completes when step succeeds', () async {
      var ran = false;
      await bestEffortBootStep('test step', () async {
        ran = true;
      });
      expect(ran, isTrue);
    });
  });
}
