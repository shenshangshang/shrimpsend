import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../device_pair.dart';
import '../../device_pair_hello.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../providers/device_provider.dart';
import '../../ui/app_ui.dart';
import '../../utils/toast.dart';

Future<void> showDevicePairSheet({
  required BuildContext context,
  String? deviceId,
  VoidCallback? onScan,
}) {
  final colors = context.appColors;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: colors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
    ),
    builder: (ctx) {
      final l10n = AppLocalizations.of(ctx);
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.md + MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.conversationConnectDevice,
                style: Theme.of(
                  ctx,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (onScan != null)
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    onScan();
                  },
                  icon: const Icon(LucideIcons.scanLine, size: 18),
                  label: Text(l10n.scanToPair),
                ),
              DevicePairPanel(
                deviceId: deviceId,
                onAdded: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class DevicePairPanel extends ConsumerStatefulWidget {
  final String? deviceId;
  final VoidCallback? onAdded;

  const DevicePairPanel({super.key, this.deviceId, this.onAdded});

  @override
  ConsumerState<DevicePairPanel> createState() => _DevicePairPanelState();
}

class _DevicePairPanelState extends ConsumerState<DevicePairPanel> {
  final _pasteController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _pasteController.dispose();
    super.dispose();
  }

  String _resolvedDeviceId() {
    final passed = widget.deviceId?.trim() ?? '';
    if (passed.isNotEmpty) return passed;
    return ref.watch(deviceInfoProvider).valueOrNull?.id ?? '';
  }

  String _pairError(AppLocalizations l10n, Object error) {
    final raw = error.toString().replaceFirst('Exception: ', '');
    switch (raw) {
      case 'cannot_pair_self':
        return l10n.pairSelf;
      case 'pair_invalid':
        return l10n.pairInvalid;
      case 'device_session_unavailable':
        return l10n.pairSessionUnavailable;
      default:
        return l10n.qrScannerPairFailed(raw);
    }
  }

  Future<void> _copyDeviceId(String deviceId) async {
    final l10n = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: deviceId));
    if (!mounted) return;
    AppToast.show(context, message: l10n.copiedDeviceId);
  }

  Future<void> _addPeer() async {
    if (_busy) return;
    final raw = _pasteController.text.trim();
    if (raw.isEmpty) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final peerId = normalizePeerDeviceId(raw);
      if (peerId == null) {
        throw Exception('pair_invalid');
      }
      await sendDevicePairHello(peerId);
      if (!mounted) return;
      ref
          .read(pairedPeersProvider.notifier)
          .upsert(deviceDtoFromPairHello(deviceId: peerId));
      ref.read(selectedDeviceIdProvider.notifier).select(peerId);
      _pasteController.clear();
      AppToast.show(context, message: l10n.peerAdded);
      widget.onAdded?.call();
    } catch (e) {
      if (!mounted) return;
      AppToast.show(context, message: _pairError(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final deviceId = _resolvedDeviceId();
    final pairUri = deviceId.isEmpty ? '' : devicePairUri(deviceId);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.pairQrHint,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.textTertiary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: AppRadius.medium,
            border: Border.all(color: colors.border),
          ),
          child: pairUri.isEmpty
              ? SizedBox(
                  width: 168,
                  height: 168,
                  child: Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                )
              : QrImageView(
                  data: pairUri,
                  version: QrVersions.auto,
                  size: 168,
                  padding: EdgeInsets.zero,
                  backgroundColor: Colors.white,
                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                ),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (deviceId.isNotEmpty)
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceMuted,
                    borderRadius: AppRadius.small,
                    border: Border.all(color: colors.border),
                  ),
                  child: Text(
                    deviceId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              IconButton.outlined(
                onPressed: () => _copyDeviceId(deviceId),
                tooltip: l10n.copyDeviceId,
                icon: const Icon(LucideIcons.copy, size: 16),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _pasteController,
                enabled: !_busy,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _addPeer(),
                decoration: InputDecoration(
                  hintText: l10n.pasteDeviceIdHint,
                  isDense: true,
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            FilledButton(
              onPressed: _busy ? null : _addPeer,
              child: _busy
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.onPrimary,
                      ),
                    )
                  : Text(l10n.pasteDeviceIdAction),
            ),
          ],
        ),
      ],
    );
  }
}
