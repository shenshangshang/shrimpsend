import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../api/api.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../providers/device_provider.dart';
import '../../providers/app_mode_provider.dart';
import '../../services/auth_session_controller.dart';
import '../../ui/app_ui.dart';
import '../../ui/platform_performance.dart';
import '../../ui/device_glyph.dart';
import '../../utils/runtime_platform.dart';
import '../devices/device_conversation_item.dart';
import '../devices/device_pair_panel.dart';
import '../home/home_list_section.dart';

/// Matches [MainLayout] / [ChatScreen] narrow breakpoint (floating tab bar inset).
const double _kNarrowLayoutBreakpoint = 768;
final _deviceSearchProvider = StateProvider.autoDispose<String>((ref) => '');

/// Sort by device state: online before checking before offline.
int _reachSortPriority(DeviceReachDetail detail) {
  if (detail.isOnline) return 0;
  if (detail.checking) return 1;
  return 2;
}

class DeviceListPanel extends ConsumerWidget {
  final bool connected;
  final String deviceName;

  /// Prefer this for matching [DeviceDto.deviceId] in lists when non-empty
  /// (e.g. [ChatScreen] sets it right after [getOrCreateDeviceId]).
  final String? myDeviceId;
  final bool statusCheckDone;
  final bool isLoggedIn;
  final AuthSessionPhase authSessionPhase;
  final VoidCallback onShowSettings;
  final VoidCallback? onSearch;
  final VoidCallback? onScanTap;
  final VoidCallback? onAddWebDavTap;
  final VoidCallback? onFileManager;
  final Future<void> Function()? onRefresh;
  final VoidCallback? onLoginTap;

  /// When false (mobile tab shell): hide bottom online-count row — tabs replace it.
  final bool showBottomStatusBar;

  /// When false (mobile tab shell): hide header file + settings — bottom bar has them.
  final bool showHeaderFileAndSettings;

  /// Narrow / mobile home: refresh in the title bar instead of only the footer row.
  final bool showHeaderRefresh;

  const DeviceListPanel({
    super.key,
    required this.connected,
    required this.deviceName,
    this.myDeviceId,
    this.statusCheckDone = true,
    this.isLoggedIn = true,
    this.authSessionPhase = AuthSessionPhase.authenticated,
    required this.onShowSettings,
    this.onSearch,
    this.onScanTap,
    this.onAddWebDavTap,
    this.onFileManager,
    this.onRefresh,
    this.onLoginTap,
    this.showBottomStatusBar = true,
    this.showHeaderFileAndSettings = true,
    this.showHeaderRefresh = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(_deviceSearchProvider);
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final colors = context.appColors;
    final isOffline = ref.watch(effectiveOfflineModeProvider);

    final currentDeviceId = () {
      final passed = myDeviceId;
      if (passed != null && passed.isNotEmpty) return passed;
      return ref.watch(deviceInfoProvider).valueOrNull?.id;
    }();
    final myDevices = ref.watch(myDevicesProvider);
    final nearbyDevices = ref.watch(nearbyDevicesProvider);
    final myIds = myDevices.map((d) => d.deviceId).toSet();
    final allDevices = [
      ...myDevices,
      ...nearbyDevices.where((d) => !myIds.contains(d.deviceId)),
    ];
    final otherDevices = allDevices
        .where((d) => d.deviceId != currentDeviceId && d.name.toLowerCase().contains(query.toLowerCase()))
        .toList();
    final selectedDeviceId = ref.watch(selectedDeviceIdProvider);
    final s3Configured = ref.watch(s3ConfiguredProvider);
    final s3Online = ref.watch(s3OnlineProvider);
    final s3Checking = ref.watch(s3CheckingProvider);
    final reachability = ref.watch(deviceReachabilityProvider);
    final showS3Section = isLoggedIn && s3Configured;
    const showDevicesSection = true;

    final sorted = [...otherDevices]
      ..sort((a, b) {
        final aReach =
            reachability[a.deviceId] ?? DeviceReachDetail.offlineDetail;
        final bReach =
            reachability[b.deviceId] ?? DeviceReachDetail.offlineDetail;
        final byReach = _reachSortPriority(aReach) - _reachSortPriority(bReach);
        if (byReach != 0) return byReach;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

    return ColoredBox(
      color: colors.surfaceMuted,
      child: Column(
        children: [
          SafeArea(bottom: false, child: Padding(padding: const EdgeInsets.fromLTRB(20, 24, 12, 12), child: Row(children: [
            Expanded(child: Text(zh ? '传输' : 'Transfers', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600))),
            TextButton.icon(onPressed: () => showDevicePairSheet(context: context, deviceId: currentDeviceId, onScan: onScanTap), icon: const Icon(LucideIcons.plus, size: 16), label: Text(l10n.conversationConnect)),
          ]))),
          Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), child: TextField(onChanged: (value) => ref.read(_deviceSearchProvider.notifier).state = value, style: const TextStyle(fontSize: 13), decoration: InputDecoration(isDense: true, prefixIcon: const Icon(LucideIcons.search, size: 17), hintText: zh ? '搜索设备' : 'Search devices'))),
          // Device list
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final scrollBottom =
                    MediaQuery.sizeOf(context).width < _kNarrowLayoutBreakpoint
                    ? 0.0
                    : 0.0;
                final listChildren = <Widget>[
                  if (showS3Section && !isOffline) ...[
                    HomeListSectionHeader(title: l10n.homeSectionCloudRelay),
                    _S3VirtualDeviceItem(
                      selected: selectedDeviceId == s3VirtualDeviceId,
                      configured: s3Configured,
                      online: s3Online,
                      checking: s3Checking,
                      onTap: () => ref
                          .read(selectedDeviceIdProvider.notifier)
                          .select(s3VirtualDeviceId),
                    ),
                  ],
                  if (showDevicesSection) ...[
                    HomeListSectionHeader(
                      title: l10n.homeSectionDevices,
                    ),
                    if (sorted.isEmpty) ...[
                      _HomeListSectionEmptyHint(
                        text: isOffline
                            ? l10n.devicePanelEmptyHintOfflineLan
                            : l10n.devicePanelEmptyNoOtherDevices,
                      ),
                    ] else
                      ...sorted.map(
                        (device) => _DeviceListReachRow(
                          key: ValueKey(device.deviceId),
                          device: device,
                          isMyDevice: myIds.contains(device.deviceId),
                          selected: selectedDeviceId == device.deviceId,
                          onTap: () => ref
                              .read(selectedDeviceIdProvider.notifier)
                              .select(device.deviceId),
                        ),
                      ),
                  ],
                ];
                Widget body = ListView(
                  padding: EdgeInsets.fromLTRB(0, 2, 0, 2 + scrollBottom),
                  children: listChildren,
                );

                if (RuntimePlatform.isMobile && onRefresh != null) {
                  body = RefreshIndicator(
                    onRefresh: onRefresh!,
                    color: theme.colorScheme.primary,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(0, 2, 0, 2 + scrollBottom),
                      children: listChildren,
                    ),
                  );
                }

                return body;
              },
            ),
          ),
          if (showHeaderFileAndSettings)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 20,
                ),
                child: Row(
                  children: [
                    Icon(
                      deviceGlyph(RuntimePlatform.osName, deviceName),
                      size: 28,
                      color: colors.textPrimary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        deviceName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    IconButton(
                      onPressed: onShowSettings,
                      tooltip: l10n.settingsTitle,
                      icon: const Icon(LucideIcons.settings, size: 22),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _HomeListSectionEmptyHint extends StatelessWidget {
  final String text;

  const _HomeListSectionEmptyHint({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(color: colors.textTertiary),
      ),
    );
  }
}

class _S3VirtualDeviceItem extends StatelessWidget {
  final bool selected;
  final bool configured;
  final bool online;
  final bool checking;
  final VoidCallback onTap;

  const _S3VirtualDeviceItem({
    required this.selected,
    required this.configured,
    required this.online,
    required this.checking,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final lightweightTap = AppPlatformPerformance.preferLightweightTapFeedback;

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xs, 4, AppSpacing.xs, 4),
      child: Material(
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: 0.1)
            : colors.surface,
        borderRadius: AppRadius.small,
        clipBehavior: lightweightTap ? Clip.none : Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.small,
          splashFactory: lightweightTap ? NoSplash.splashFactory : null,
          highlightColor: lightweightTap ? Colors.transparent : null,
          focusColor: lightweightTap ? Colors.transparent : null,
          hoverColor: lightweightTap
              ? colors.surfaceMuted.withValues(alpha: 0.7)
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0EA5E9).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: Icon(
                          LucideIcons.cloud,
                          size: 22,
                          color: Color(0xFF0EA5E9),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: -2,
                      right: -2,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: checking
                              ? colors.warning
                              : !configured
                              ? colors.textTertiary.withValues(alpha: 0.4)
                              : online
                              ? colors.success
                              : colors.warning,
                          shape: BoxShape.circle,
                          border: Border.all(color: colors.surface, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.chatS3RelayTitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        checking
                            ? l10n.chatS3StatusChecking
                            : !configured
                            ? l10n.chatS3StatusNotConfigured
                            : online
                            ? l10n.chatS3StatusOnlineSendAll
                            : l10n.chatS3StatusUnavailableCheck,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.textTertiary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Subscribes only to this [device]'s reach row so probe updates for other peers
/// do not rebuild this list tile.
class _DeviceListReachRow extends ConsumerWidget {
  const _DeviceListReachRow({
    super.key,
    required this.device,
    required this.isMyDevice,
    required this.selected,
    required this.onTap,
  });

  final DeviceDto device;
  final bool isMyDevice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(
      deviceReachabilityProvider.select(
        (m) => m[device.deviceId] ?? DeviceReachDetail.offlineDetail,
      ),
    );
    final reachStatus = detail.uiReachStatus;
    return DeviceConversationItem(
      device: device,
      isMyDevice: isMyDevice,
      selected: selected,
      reachStatus: reachStatus,
      onTap: onTap,
    );
  }
}
