import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../api/webdav.dart';
import '../l10n/generated/app_localizations.dart';
import '../providers/webdav_provider.dart';
import '../ui/app_ui.dart';
import '../ui/product_scaffold.dart';
import '../widgets/webdav/webdav_connection_actions.dart';
import 'webdav_connection_screen.dart';
import 'webdav_shell_screen.dart';

class WebDavSettingsScreen extends ConsumerWidget {
  const WebDavSettingsScreen({super.key});
  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const WebDavConnectionScreen()),
    );
    if (saved == true && context.mounted)
      await ref.read(webDavConnectionsProvider.notifier).refresh();
  }

  void _open(BuildContext context, WebDavConnectionSummary connection) =>
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WebDavShellScreen(connection: connection),
        ),
      );
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final l10n = AppLocalizations.of(context);
    final colors = context.appColors;
    final connections = ref.watch(webDavConnectionsProvider);
    return ProductScaffold(
      section: ProductSection.files,
      filesLocation: '/files/cloud',
      appBar: AppBar(
        title: Text(zh ? '云端文件' : 'Cloud files'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: FilledButton.icon(
              onPressed: () => _add(context, ref),
              icon: const Icon(LucideIcons.plus, size: 16),
              label: Text(l10n.webdavAddConnection),
            ),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  zh
                      ? '连接你的 WebDAV 存储，直接浏览、上传和下载。新连接只保存在这台设备，无需登录虾传账号。'
                      : 'Browse, upload and download from your WebDAV storage. New connections belong to this device; no ShrimpSend account is required.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: connections.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, _) => Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(l10n.homeWebDavLoadFailed),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: () => ref
                                .read(webDavConnectionsProvider.notifier)
                                .refresh(),
                            child: Text(l10n.homeWebDavRetry),
                          ),
                        ],
                      ),
                    ),
                    data: (rows) {
                      if (rows.isEmpty)
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                LucideIcons.cloud,
                                size: 36,
                                color: colors.textSecondary,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                zh ? '还没有云端连接' : 'No cloud connections yet',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                zh
                                    ? '连接后，文件仍保存在你自己的存储中。'
                                    : 'Your files stay in your own storage.',
                                style: TextStyle(color: colors.textSecondary),
                              ),
                              const SizedBox(height: 24),
                              FilledButton.icon(
                                onPressed: () => _add(context, ref),
                                icon: const Icon(LucideIcons.plus, size: 16),
                                label: Text(l10n.webdavAddConnection),
                              ),
                            ],
                          ),
                        );
                      return RefreshIndicator(
                        onRefresh: () => ref
                            .read(webDavConnectionsProvider.notifier)
                            .refresh(),
                        child: ListView.separated(
                          itemCount: rows.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final connection = rows[index];
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                vertical: 12,
                              ),
                              leading: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: colors.accentSoft,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  LucideIcons.hardDrive,
                                  size: 22,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                              title: Text(
                                connection.name,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              subtitle: Text(
                                '${Uri.tryParse(connection.baseUrl)?.host ?? connection.baseUrl} · ${connection.id < 0 ? (zh ? '本机连接' : 'On this device') : (zh ? '原账号连接' : 'Account connection')}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12),
                              ),
                              onTap: () => _open(context, connection),
                              trailing: IconButton(
                                tooltip: zh ? '管理连接' : 'Manage connection',
                                icon: const Icon(
                                  LucideIcons.ellipsis,
                                  size: 20,
                                ),
                                onPressed: () => showWebDavConnectionMenu(
                                  context,
                                  ref,
                                  connection,
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
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
