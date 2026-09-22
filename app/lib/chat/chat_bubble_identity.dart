/// Flyer Chat keys list children by `message.id`. [ChatAnimatedList] on
/// `update` only replaces `_oldList[index]` and does not notify
/// [SliverAnimatedList] of a key change. Retargeting an on-screen bubble to a
/// different id — or inserting a second row with an id already in the list —
/// crashes [ChatAnimatedListReversed] with Duplicate GlobalKey /
/// `_elements.contains`.
const String kLocalBubbleIdPrefix = 'local_';

String localBubbleId(String localId) => '$kLocalBubbleIdPrefix$localId';

/// Receiver UI identity for a file transfer. Prefer the sender's
/// `payload.localId` so WebRTC offer, Centrifugo `file` persist, and progress
/// updates share one list row without changing keys.
String fileReceiveBubbleId({
  required String? senderLocalId,
  required String fallbackId,
}) {
  final id = senderLocalId?.trim() ?? '';
  if (id.isEmpty) return fallbackId;
  return localBubbleId(id);
}

/// True when applying [serverId] onto [existingBubbleId] would put two list
/// children under the same [ValueKey].
bool wouldDuplicateChatBubbleId({
  required String existingBubbleId,
  required String serverId,
  required bool serverIdAlreadyOnScreen,
}) {
  if (existingBubbleId == serverId) return false;
  return serverIdAlreadyOnScreen;
}
