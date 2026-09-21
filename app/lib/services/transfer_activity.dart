import 'package:flutter/foundation.dart';

enum TransferActivityStatus { active, paused, completed, failed }

/// A read-only view of the transfer engines. Commands stay with their owning engine.
class TransferActivityItem {
  final String id;
  final String name;
  final int? size;
  final double? progress;
  final String? channel;
  final String? speed;
  final String? localPath;
  final String? error;
  final TransferActivityStatus status;
  final DateTime? createdAt;
  final VoidCallback? pause;
  final AsyncCallback? resume;
  final VoidCallback? openConversation;
  const TransferActivityItem({
    required this.id,
    required this.name,
    required this.status,
    this.size,
    this.progress,
    this.channel,
    this.speed,
    this.localPath,
    this.error,
    this.createdAt,
    this.pause,
    this.resume,
    this.openConversation,
  });
}

class TransferActivity {
  static List<TransferActivityItem> Function()? read;
}
