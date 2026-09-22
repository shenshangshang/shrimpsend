import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../ui/product_scaffold.dart';

class FileConnectionsScreen extends StatelessWidget {
  const FileConnectionsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return ProductScaffold(
      section: ProductSection.files,
      filesLocation: '/files/connections',
      appBar: AppBar(title: Text(zh ? '连接设置' : 'Connections')),
      body: ListView(
        padding: const EdgeInsets.all(28),
        children: [
          Text(
            zh
                ? '连接云端文件，或配置无法直连时使用的备用通道。'
                : 'Connect cloud storage, or configure a fallback when a direct connection is unavailable.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 28),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(LucideIcons.cloud),
            title: const Text('WebDAV'),
            subtitle: Text(
              zh
                  ? '浏览和管理网盘、NAS 上的文件'
                  : 'Browse files on your cloud drive or NAS',
            ),
            trailing: const Icon(LucideIcons.chevronRight, size: 18),
            onTap: () => openProductRoute(context, '/settings/webdav'),
          ),
          const Divider(height: 32),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(LucideIcons.database),
            title: Text(zh ? '对象存储 · S3' : 'Object storage · S3'),
            subtitle: Text(
              zh ? '用于云端文件传递和备用中转' : 'Cloud file transfers and fallback relay',
            ),
            trailing: const Icon(LucideIcons.chevronRight, size: 18),
            onTap: () => openProductRoute(context, '/settings/s3'),
          ),
        ],
      ),
    );
  }
}
