import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api/device_send_quota.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../providers/auth_provider.dart';
import '../../providers/device_send_quota_provider.dart';
import '../../ui/app_ui.dart';
import '../app_confirm_dialog.dart';

class DeviceSendQuotaBar extends ConsumerStatefulWidget {
  const DeviceSendQuotaBar({super.key});

  @override
  ConsumerState<DeviceSendQuotaBar> createState() => _DeviceSendQuotaBarState();
}

class _DeviceSendQuotaBarState extends ConsumerState<DeviceSendQuotaBar> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(deviceSendQuotaProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(authProvider).isLoggedIn) {
      return const SizedBox.shrink();
    }
    final quota = ref.watch(deviceSendQuotaProvider);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = context.appColors;
    final message = quota?.message;
    final signaling = quota?.signaling;
    final limited = quota?.limited == true || quota?.anyExhausted == true;
    final fg = limited ? colors.warning : colors.textSecondary;

    return Material(
      color: colors.surfaceMuted,
      child: InkWell(
        onTap: () => showDeviceSendQuotaDialog(
          context,
          quota: quota,
          limited: limited,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xxs,
          ),
          child: Row(
            children: [
              Icon(LucideIcons.gauge, size: 14, color: fg),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  [
                    l10n.deviceSendQuotaHint,
                    l10n.deviceSendQuotaMessage(
                      message?.used ?? 0,
                      message?.limit ?? 90,
                    ),
                    l10n.deviceSendQuotaSignaling(
                      signaling?.used ?? 0,
                      signaling?.limit ?? 600,
                    ),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: fg,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showDeviceSendQuotaDialog(
  BuildContext context, {
  required DeviceSendQuota? quota,
  required bool limited,
}) {
  final l10n = AppLocalizations.of(context);
  final message = quota?.message;
  final signaling = quota?.signaling;
  final seconds = quota?.retryAfterSeconds ?? 1;
  final String content;
  if (limited && quota?.kind == 'signaling') {
    content = l10n.deviceSendQuotaSignalingBody(
      signaling?.used ?? signaling?.limit ?? 600,
      signaling?.limit ?? 600,
      seconds,
    );
  } else if (limited && (quota?.kind == 'message' || quota?.message.exhausted == true)) {
    content = l10n.deviceSendQuotaMessageBody(
      message?.used ?? message?.limit ?? 90,
      message?.limit ?? 90,
      seconds,
    );
  } else {
    content = l10n.deviceSendQuotaInfoBody(
      message?.used ?? 0,
      message?.limit ?? 90,
      signaling?.used ?? 0,
      signaling?.limit ?? 600,
    );
  }
  return AppConfirmDialog.show(
    context,
    title: limited ? l10n.deviceSendQuotaTitle : l10n.deviceSendQuotaHint,
    content: content,
    confirmLabel: l10n.deviceSendQuotaGotIt,
    icon: LucideIcons.gauge,
    showCancel: false,
  ).then((_) {});
}
