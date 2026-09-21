import 'package:flutter/material.dart';
import '../../api/api.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../providers/device_provider.dart';
import '../../ui/app_ui.dart';
import '../../ui/device_glyph.dart';

class DeviceConversationItem extends StatelessWidget {
  final DeviceDto device;
  final bool isMyDevice;
  final bool selected;
  final DeviceReachStatus reachStatus;
  final String? lastMessage;
  final VoidCallback onTap;
  const DeviceConversationItem({
    super.key,
    required this.device,
    required this.isMyDevice,
    required this.selected,
    required this.reachStatus,
    this.lastMessage,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final online =
        reachStatus == DeviceReachStatus.online ||
        reachStatus == DeviceReachStatus.pullOnline;
    final checking = reachStatus == DeviceReachStatus.checking;
    final name = conversationDeviceName(
      device.name,
      device.deviceId,
      device.platform,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? colors.accentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              child: Row(
                children: [
                  Icon(
                    deviceGlyph(device.platform, name),
                    size: 30,
                    color: colors.textPrimary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 5),
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
                            Flexible(
                              child: Text(
                                online
                                    ? l10n.conversationAvailable
                                    : checking
                                    ? l10n.chatDeviceChecking
                                    : l10n.chatDeviceOffline,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 12,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
