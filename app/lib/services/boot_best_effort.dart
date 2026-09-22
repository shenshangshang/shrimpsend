import '../logger.dart';

/// Runs non-fatal bootstrap work. Failures are logged and startup continues.
Future<void> bestEffortBootStep(
  String label,
  Future<void> Function() step,
) async {
  try {
    await step();
    logBoot.info('boot: $label done');
  } catch (e, st) {
    logBoot.warning('boot: $label failed (continuing): $e', e, st);
  }
}
