import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../device_id.dart';
import '../logger.dart';
import '../providers/realtime_hub_provider.dart';

/// Keeps [RealtimeHub] running whenever the app has a chance of reaching the
/// network. Login is not required; IM identity is the local device.
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
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      unawaited(_onConnectivity(results));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_ensureStarted());
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

  Future<void> _onConnectivity(List<ConnectivityResult> results) async {
    final offline = results.isEmpty ||
        results.every((r) => r == ConnectivityResult.none);
    if (offline) {
      return;
    }
    await _ensureStarted();
    await ref.read(realtimeHubProvider).onConnectivityChanged();
  }

  Future<void> _ensureStarted() async {
    final hub = ref.read(realtimeHubProvider);
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
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
