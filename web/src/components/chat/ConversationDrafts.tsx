'use client';
import { createContext, useContext, useState, type ReactNode } from 'react';
const DraftsContext = createContext<{ drafts: Record<string, string>; setDraft: (device: string, value: string) => void } | null>(null);
export function ConversationDrafts({ children }: { children: ReactNode }) {
  const [drafts, setDrafts] = useState<Record<string, string>>({});
  return <DraftsContext.Provider value={{ drafts, setDraft: (device, value) => setDrafts(previous => ({ ...previous, [device]: value })) }}>{children}</DraftsContext.Provider>;
}
export function useConversationDraft(device: string | null): [string, (value: string) => void] {
  const state = useContext(DraftsContext);
  if (!state) throw new Error('ConversationDrafts provider missing');
  return [state.drafts[device ?? ''] ?? '', value => state.setDraft(device ?? '', value)];
}
