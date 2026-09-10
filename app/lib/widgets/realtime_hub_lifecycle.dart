import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device_id.dart';
import '../logger.dart';
import '../providers/auth_session_provider.dart';
import '../providers/realtime_hub_provider.dart';
import '../services/auth_session_controller.dart';

/// Keeps [RealtimeHub] running for the whole logged-in session.
class RealtimeHubLifecycle extends ConsumerStatefulWidget {
  const RealtimeHubLifecycle({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<RealtimeHubLifecycle> createState() =>
      _RealtimeHubLifecycleState();
}

class _RealtimeHubLifecycleState extends ConsumerState<RealtimeHubLifecycle>
    with WidgetsBindingObserver {
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _connectivitySub = Connectivity().onConnectivityChanged.listen((_) {
      unawaited(ref.read(realtimeHubProvider).onConnectivityChanged());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(realtimeHubProvider).onAppResumed());
    }
  }

  Future<void> _syncSession(AuthSessionPhase phase) async {
    final hub = ref.read(realtimeHubProvider);
    if (phase == AuthSessionPhase.authenticated) {
      if (_started) {
        unawaited(hub.onAppResumed());
        return;
      }
      _started = true;
      try {
        final deviceId = await getOrCreateDeviceId();
        final name = await getDeviceName();
        await hub.start(deviceId: deviceId, deviceName: name);
      } catch (e) {
        logRealtime.warning('realtime hub lifecycle start failed: $e');
        _started = false;
      }
      return;
    }
    if (_started) {
      _started = false;
      await hub.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthSessionPhase>(authSessionPhaseProvider, (prev, next) {
      unawaited(_syncSession(next));
    });
    final phase = ref.watch(authSessionPhaseProvider);
    if (!_started && phase == AuthSessionPhase.authenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_syncSession(phase));
      });
    }
    return widget.child;
  }
}
