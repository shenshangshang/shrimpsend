import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../api/webdav.dart';
import '../providers/webdav_provider.dart';
import '../services/transfer_activity.dart';
import '../services/transfer_record.dart';
import '../services/transfer_state_manager.dart';
import '../services/transfer_status.dart';
import '../services/webdav_session.dart';
import '../services/webdav_transfer_service.dart';
import '../ui/app_ui.dart';
import '../ui/product_scaffold.dart';
import '../utils/file_utils.dart';
import '../utils/open_directory.dart';
import '../widgets/file_icon_widget.dart';

class TransferActivityScreen extends StatefulWidget {
  const TransferActivityScreen({super.key});
  @override
  State<TransferActivityScreen> createState() => _TransferActivityScreenState();
}

class _TransferActivityScreenState extends State<TransferActivityScreen> {
  Timer? _timer;
  List<TransferRecord> _persisted = [];
  bool _reading = false;
  int _ticks = 0;
  String _filter = 'active';
  String? _error;
  final Set<String> _busy = {};
  @override
  void initState() {
    super.initState();
    _readRecords();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!mounted) return;
      if (++_ticks % 10 == 0) _readRecords();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _readRecords() async {
    if (_reading) return;
    _reading = true;
    try {
      final rows = await TransferStateManager.instance.getResumableTransfers();
      if (mounted)
        setState(() {
          _persisted = rows;
          _error = null;
        });
    } catch (_) {
      if (mounted)
        setState(
          () => _error = Localizations.localeOf(context).languageCode == 'zh'
              ? '部分历史任务暂时无法读取，请重试。'
              : 'Some saved transfers could not be loaded. Try again.',
        );
    } finally {
      _reading = false;
    }
  }

  Future<void> _resumeWebDav(TransferRecord record) async {
    final connections = await listWebDavConnections();
    final connection = connections
        .where((c) => c.id.toString() == record.webdavConnectionId)
        .firstOrNull;
    if (connection == null) throw StateError('WebDAV connection unavailable');
    final client = WebDavClient(await resolveWebDavCredentials(connection.id));
    if (record.direction == 'download') {
      await WebDavTransferService.instance.resumeDownload(
        client: client,
        connection: connection,
        record: record,
      );
    } else {
      await WebDavTransferService.instance.resumeUpload(
        client: client,
        connection: connection,
        record: record,
      );
    }
    await _readRecords();
  }

  List<TransferActivityItem> _items() {
    final result = {
      for (final item
          in TransferActivity.read?.call() ?? <TransferActivityItem>[])
        item.id: item,
    };
    for (final record in _persisted) {
      if (result.containsKey(record.transferId) ||
          result.containsKey('local_${record.transferId}'))
        continue;
      result[record.transferId] = TransferActivityItem(
        id: record.transferId,
        name: record.fileName,
        size: record.fileSize,
        channel: record.channel,
        progress: record.fileSize > 0
            ? record.transferredBytes / record.fileSize
            : null,
        createdAt: record.createdAt,
        error: record.errorMessage,
        status: record.status == TransferStatus.failed
            ? TransferActivityStatus.failed
            : record.status == TransferStatus.inProgress
            ? TransferActivityStatus.active
            : TransferActivityStatus.paused,
        resume:
            record.channel == 'webdav' &&
                record.status != TransferStatus.inProgress
            ? () => _resumeWebDav(record)
            : null,
      );
    }
    for (final snap in WebDavTransferService.instance.allSnapshots) {
      final record = _persisted
          .where((r) => r.transferId == snap.transferId)
          .firstOrNull;
      result[snap.transferId] = TransferActivityItem(
        id: snap.transferId,
        name: snap.fileName,
        size: snap.fileSize,
        channel: 'webdav',
        progress: snap.fileSize > 0
            ? snap.transferredBytes / snap.fileSize
            : null,
        speed: snap.bytesPerSecond > 0
            ? '${formatFileSize(snap.bytesPerSecond.round())}/s'
            : null,
        createdAt: record?.createdAt,
        error: snap.errorMessage,
        status: snap.status == TransferStatus.completed
            ? TransferActivityStatus.completed
            : snap.status == TransferStatus.failed
            ? TransferActivityStatus.failed
            : snap.status == TransferStatus.inProgress
            ? TransferActivityStatus.active
            : TransferActivityStatus.paused,
        pause: snap.status == TransferStatus.inProgress
            ? () {
                WebDavTransferService.instance
                    .pause(snap.transferId)
                    .then((_) => _readRecords());
              }
            : null,
        resume:
            record != null &&
                snap.status != TransferStatus.inProgress &&
                snap.status != TransferStatus.completed
            ? () => _resumeWebDav(record)
            : null,
      );
    }
    return result.values.toList()..sort(
      (a, b) => (b.createdAt ?? DateTime(1970)).compareTo(
        a.createdAt ?? DateTime(1970),
      ),
    );
  }

  Future<void> _resume(TransferActivityItem item) async {
    if (_busy.contains(item.id)) return;
    setState(() => _busy.add(item.id));
    try {
      await item.resume?.call();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              Localizations.localeOf(context).languageCode == 'zh'
                  ? '任务未能恢复，请检查连接后重试。'
                  : 'Unable to resume. Check the connection and try again.',
            ),
          ),
        );
    } finally {
      if (mounted) setState(() => _busy.remove(item.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    final colors = context.appColors;
    final all = _items();
    final items = all
        .where(
          (item) => _filter == 'completed'
              ? item.status == TransferActivityStatus.completed
              : _filter == 'failed'
              ? item.status == TransferActivityStatus.failed
              : item.status == TransferActivityStatus.active ||
                    item.status == TransferActivityStatus.paused,
        )
        .toList();
    return ProductScaffold(
      section: ProductSection.files,
      filesLocation: '/files/tasks',
      appBar: AppBar(
        title: Text(zh ? '传输任务' : 'Transfers'),
        actions: [
          TextButton(
            onPressed: all.any((item) => item.pause != null)
                ? () {
                    for (final item in all) {
                      item.pause?.call();
                    }
                  }
                : null,
            child: Text(zh ? '全部暂停' : 'Pause all'),
          ),
          const SizedBox(width: 20),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
            child: Row(
              children: [
                for (final (value, label) in [
                  ('active', zh ? '进行中' : 'In progress'),
                  ('completed', zh ? '已完成' : 'Completed'),
                  ('failed', zh ? '未完成' : 'Failed'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _filter == value,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _filter = value),
                    ),
                  ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(color: colors.danger, fontSize: 13),
                    ),
                  ),
                  TextButton(
                    onPressed: _readRecords,
                    child: Text(zh ? '重试' : 'Retry'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.arrowDownUp,
                          size: 36,
                          color: colors.textTertiary,
                        ),
                        const SizedBox(height: 18),
                        Text(
                          zh ? '这里暂时没有任务' : 'No transfers here',
                          style: TextStyle(color: colors.textSecondary),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: () => openProductRoute(context, '/'),
                          child: Text(zh ? '去传输文件' : 'Send a file'),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(28, 12, 28, 28),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 14),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final label = switch (item.status) {
                        TransferActivityStatus.active =>
                          zh ? '传输中' : 'Transferring',
                        TransferActivityStatus.paused => zh ? '已暂停' : 'Paused',
                        TransferActivityStatus.completed =>
                          zh ? '已完成' : 'Completed',
                        TransferActivityStatus.failed => zh ? '传输失败' : 'Failed',
                      };
                      return Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          border: Border.all(color: colors.border),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                FileIconWidget(
                                  category: getFileCategory(item.name),
                                  size: 34,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        '${formatFileSize(item.size)} · $label${item.channel == null ? '' : ' · ${item.channel!.toUpperCase()}'}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color:
                                              item.status ==
                                                  TransferActivityStatus.failed
                                              ? colors.danger
                                              : colors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (item.pause != null)
                                  IconButton(
                                    onPressed: item.pause,
                                    tooltip: zh ? '暂停' : 'Pause',
                                    icon: const Icon(
                                      LucideIcons.pause,
                                      size: 18,
                                    ),
                                  ),
                                if (item.resume != null)
                                  TextButton(
                                    onPressed: _busy.contains(item.id)
                                        ? null
                                        : () => _resume(item),
                                    child: Text(
                                      _busy.contains(item.id)
                                          ? (zh ? '恢复中…' : 'Resuming…')
                                          : (zh ? '继续' : 'Resume'),
                                    ),
                                  ),
                              ],
                            ),
                            if (item.status == TransferActivityStatus.active ||
                                item.status ==
                                    TransferActivityStatus.paused) ...[
                              const SizedBox(height: 16),
                              LinearProgressIndicator(
                                value: item.progress?.clamp(0.0, 1.0),
                                minHeight: 4,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${item.progress == null ? (zh ? '正在连接…' : 'Connecting…') : '${(item.progress! * 100).clamp(0, 100).round()}%'}${item.speed == null ? '' : ' · ${item.speed}'}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ],
                            if (item.error != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Text(
                                  item.error!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.danger,
                                  ),
                                ),
                              ),
                            if (item.localPath != null ||
                                item.openConversation != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Wrap(
                                  spacing: 12,
                                  children: [
                                    if (item.localPath != null)
                                      TextButton.icon(
                                        onPressed: () =>
                                            revealFileInFileManager(
                                              item.localPath!,
                                            ),
                                        icon: const Icon(
                                          LucideIcons.folderOpen,
                                          size: 15,
                                        ),
                                        label: Text(zh ? '显示文件' : 'Show file'),
                                      ),
                                    if (item.openConversation != null)
                                      TextButton(
                                        onPressed: item.openConversation,
                                        child: Text(
                                          zh ? '查看会话' : 'Open conversation',
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
