import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Only explicit local nicknames override a peer's advertised name.
class DeviceAliases extends StateNotifier<Map<String, String>> {
  DeviceAliases() : super({}) {
    _ready = _load();
  }
  static const _key = 'shrimpsend_device_aliases';
  late final Future<void> _ready;
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = jsonDecode(prefs.getString(_key) ?? '{}') as Map;
      if (mounted)
        state = {
          for (final e in raw.entries)
            if (e.key is String && e.value is String)
              e.key as String: e.value as String,
        };
    } catch (_) {}
  }

  Future<void> rename(String id, String name) async {
    await _ready;
    if (!mounted) return;
    final next = {...state};
    if (name.trim().isEmpty) {
      next.remove(id);
    } else {
      next[id] = name.trim();
    }
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(state));
  }
}

final deviceAliasesProvider =
    StateNotifierProvider<DeviceAliases, Map<String, String>>(
      (_) => DeviceAliases(),
    );
