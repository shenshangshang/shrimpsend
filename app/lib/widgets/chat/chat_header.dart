import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../providers/device_provider.dart';
import '../../ui/app_ui.dart';
import '../../ui/device_glyph.dart';

class ChatHeader extends ConsumerWidget implements PreferredSizeWidget {
  final bool showBackButton;
  final VoidCallback? onBack;
  final VoidCallback? onFileManager;
  final VoidCallback? onOpenS3Settings;
  final VoidCallback? onSessionDeviceSettings;
  final bool isSelectionMode;
  final int selectedCount;
  final int totalCount;
  final VoidCallback? onExitSelection;
  final VoidCallback? onToggleSelectAll;
  final VoidCallback? onDeleteSelected;
  const ChatHeader({
    super.key,
    this.showBackButton = false,
    this.onBack,
    this.onFileManager,
    this.onOpenS3Settings,
    this.onSessionDeviceSettings,
    this.isSelectionMode = false,
    this.selectedCount = 0,
    this.totalCount = 0,
    this.onExitSelection,
    this.onToggleSelectAll,
    this.onDeleteSelected,
  });

  @override
  Size get preferredSize => const Size.fromHeight(88);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final selectedId = ref.watch(selectedDeviceIdProvider);
    final devices = [
      ...ref.watch(myDevicesProvider),
      ...ref.watch(nearbyDevicesProvider),
    ];
    final device = devices.where((d) => d.deviceId == selectedId).firstOrNull;
    final detail =
        ref.watch(deviceReachabilityProvider)[selectedId] ??
        DeviceReachDetail.offlineDetail;
    final isS3 = selectedId == s3VirtualDeviceId;
    final s3Online = ref.watch(s3OnlineProvider);
    final s3Checking = ref.watch(s3CheckingProvider);
    final wide = MediaQuery.sizeOf(context).width >= 768;
    final online = isS3 ? s3Online : detail.isOnline;
    final checking = isS3 ? s3Checking : detail.checking;
    final name = isS3
        ? l10n.chatS3RelayTitle
        : device == null
        ? l10n.chatPickDeviceToStart
        : conversationDeviceName(device.name, device.deviceId, device.platform);
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: wide ? 32 : 12,
            vertical: wide ? 18 : 12,
          ),
          child: Row(
            children: [
              if (showBackButton || isSelectionMode)
                IconButton(
                  onPressed: isSelectionMode ? onExitSelection : onBack,
                  icon: const Icon(LucideIcons.arrowLeft, size: 22),
                  tooltip: l10n.chatTooltipBackDeviceList,
                ),
              if (!isSelectionMode) ...[
                Icon(
                  isS3
                      ? LucideIcons.cloud
                      : deviceGlyph(device?.platform, name),
                  size: 32,
                  color: colors.textPrimary,
                ),
                const SizedBox(width: 16),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isSelectionMode
                          ? l10n.chatSelectedCount(selectedCount)
                          : name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontSize: wide ? 18 : 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (!isSelectionMode) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.circle,
                            size: 6,
                            color: online
                                ? theme.colorScheme.primary
                                : checking
                                ? colors.warning
                                : colors.textTertiary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            online
                                ? l10n.conversationAvailable
                                : checking
                                ? l10n.chatDeviceChecking
                                : l10n.chatDeviceOffline,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 12,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              if (isSelectionMode) ...[
                TextButton(
                  onPressed: onToggleSelectAll,
                  child: Text(
                    selectedCount == totalCount
                        ? l10n.chatDeselectAll
                        : l10n.chatSelectAll,
                  ),
                ),
                IconButton(
                  onPressed: selectedCount == 0 ? null : onDeleteSelected,
                  tooltip: l10n.chatTooltipDelete,
                  icon: Icon(
                    LucideIcons.trash2,
                    size: 20,
                    color: colors.danger,
                  ),
                ),
              ] else if (isS3 && onOpenS3Settings != null)
                IconButton(
                  onPressed: onOpenS3Settings,
                  tooltip: l10n.chatTooltipS3Settings,
                  icon: const Icon(LucideIcons.ellipsis, size: 22),
                )
              else if (device != null && onSessionDeviceSettings != null)
                IconButton(
                  onPressed: onSessionDeviceSettings,
                  tooltip: l10n.chatTooltipSessionSettings,
                  icon: const Icon(LucideIcons.ellipsis, size: 22),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
