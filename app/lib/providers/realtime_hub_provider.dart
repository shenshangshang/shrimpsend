import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/realtime_hub.dart';

final realtimeHubProvider = Provider<RealtimeHub>((ref) {
  final hub = RealtimeHub();
  ref.onDispose(() {
    hub.dispose();
  });
  return hub;
});
