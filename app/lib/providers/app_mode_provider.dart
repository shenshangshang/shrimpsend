import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';
import 'realtime_hub_provider.dart';

enum AppMode { online, offline }

final appModeProvider = Provider<AppMode>((ref) {
  final auth = ref.watch(authProvider);
  return auth.isLoggedIn ? AppMode.online : AppMode.offline;
});

final isOfflineModeProvider = Provider<bool>((ref) {
  return ref.watch(appModeProvider) == AppMode.offline;
});

final isOnlineModeProvider = Provider<bool>((ref) {
  return ref.watch(appModeProvider) == AppMode.online;
});

/// Device signaling is independent of billing login. LAN remains usable offline.
final deviceConnectionProvider = StreamProvider<bool>((ref) async* {
  final hub = ref.watch(realtimeHubProvider);
  yield hub.isConnected;
  yield* hub.connectedChanges;
});
final effectiveOfflineModeProvider = Provider<bool>((ref) {
  return !(ref.watch(deviceConnectionProvider).valueOrNull ??
      ref.read(realtimeHubProvider).isConnected);
});
