import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../l10n/generated/app_localizations.dart';
import '../ui/app_ui.dart';
import '../utils/file_utils.dart';
import 'file_icon_widget.dart';

class FileCardBubble extends StatelessWidget {
  final String fileName;
  final int? size;
  final String? transferType;
  final bool hasDownload;
  final bool isSentByMe;
  final String? filePath;

  const FileCardBubble({
    super.key,
    required this.fileName,
    this.size,
    this.transferType,
    this.hasDownload = false,
    required this.isSentByMe,
    this.filePath,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final l10n = AppLocalizations.of(context);
    final bubbleColor = colors.surface;
    final onBubble = colors.textPrimary;
    final muted = colors.textSecondary;
    final accent = theme.colorScheme.primary;
    final sizeStr = formatFileSize(size);

    return Container(
      constraints: const BoxConstraints(maxWidth: 340),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: AppRadius.small,
        border: Border.all(color: colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FileIconWidget(
            category: getFileCategory(fileName),
            size: 34,
            filePath: filePath,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        fileName,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: onBubble,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (sizeStr.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    '$sizeStr${filePath != null ? ' · ${isSentByMe ? l10n.conversationSent : l10n.conversationSaved}' : ''}',
                    style: TextStyle(color: muted, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (filePath != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                l10n.chatMenuOpen,
                style: theme.textTheme.labelLarge?.copyWith(color: accent),
              ),
            ),
          if (hasDownload && filePath == null)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(LucideIcons.download, size: 22, color: accent),
            ),
        ],
      ),
    );
  }
}
