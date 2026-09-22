type ConversationMessage = {
  id?: number;
  _localId?: string;
  fromDeviceId: string;
  toDeviceId?: string;
  threadKey?: string;
  ts: number;
  payload?: unknown;
};

/** Route by device identities; a guest's account prefix differs on each end. */
export function belongsToConversation(message: ConversationMessage, me: string, peer: string | null): boolean {
  if (!peer) return false;
  if (peer === '__s3_cloud__') return message.threadKey?.endsWith('|kind:s3_cloud') === true;
  const payload = message.payload as { targetDeviceId?: string; targetDeviceIds?: string[] } | undefined;
  const to = message.toDeviceId ?? payload?.targetDeviceId;
  if (message.fromDeviceId === peer) return !to || to === me;
  if (message.fromDeviceId !== me) return false;
  return to === peer || payload?.targetDeviceIds?.includes(peer) === true;
}

/** Merge history without losing in-flight transfers or newly delivered messages. */
export function mergeMessageHistory<T extends ConversationMessage>(current: T[], history: T[]): T[] {
  const rows = [...current];
  for (const incoming of history) {
    const localId = incoming._localId ?? (incoming.payload as { localId?: string })?.localId;
    const index = rows.findIndex(row =>
      (incoming.id != null && row.id === incoming.id) ||
      (!!localId && localId === (row._localId ?? (row.payload as { localId?: string })?.localId)));
    if (index < 0) rows.push(incoming);
    else rows[index] = { ...incoming, ...rows[index], id: incoming.id };
  }
  return rows.sort((a, b) => a.ts - b.ts);
}
