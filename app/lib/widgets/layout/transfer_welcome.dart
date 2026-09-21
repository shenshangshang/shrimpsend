import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../providers/device_provider.dart';
import '../../ui/app_ui.dart';
import '../devices/device_pair_panel.dart';

class TransferWelcome extends ConsumerWidget {
  final String? deviceId;
  const TransferWelcome({super.key, this.deviceId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final mine = ref.watch(myDevicesProvider);
    final nearby = ref.watch(nearbyDevicesProvider);
    final unique = {
      for (final device in [...mine, ...nearby]) device.deviceId: device,
    };
    final devices = unique.values
        .where((device) => device.deviceId != deviceId)
        .take(4)
        .toList();
    return Align(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(40, 72, 40, 32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                LucideIcons.laptop,
                size: 42,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                zh ? '设备之间，轻松传递。' : 'Your devices. Simply connected.',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                zh
                    ? '选择一台设备，发送文件或文字。无需登录，也能在局域网中互传。'
                    : 'Choose a device to send files or text. No account needed for local transfers.',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.8,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 32),
              if (devices.isNotEmpty) ...[
                Text(
                  zh ? '选择设备' : 'Choose a device',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                for (final device in devices)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 0,
                      vertical: 6,
                    ),
                    leading: const Icon(LucideIcons.monitor, size: 24),
                    title: Text(
                      device.name,
                      style: const TextStyle(fontSize: 15),
                    ),
                    trailing: const Icon(LucideIcons.chevronRight, size: 17),
                    onTap: () => ref
                        .read(selectedDeviceIdProvider.notifier)
                        .select(device.deviceId),
                  ),
                const SizedBox(height: 20),
              ],
              FilledButton.icon(
                onPressed: () =>
                    showDevicePairSheet(context: context, deviceId: deviceId),
                icon: const Icon(LucideIcons.plus, size: 17),
                label: Text(zh ? '连接新设备' : 'Connect a device'),
              ),
              const SizedBox(height: 36),
              const Divider(),
              const SizedBox(height: 16),
              Text(
                zh
                    ? '文件直接保存到接收目录。连接中断后，可以接着传。'
                    : 'Files go straight to your receive folder. Interrupted transfers can resume.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.8,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
