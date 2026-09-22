'use client';

import { useState } from 'react';
import { usePathname } from 'next/navigation';
import { RealtimeProvider } from '@/contexts/RealtimeContext';
import { ChatProvider } from '@/contexts/ChatContext';
import { ConversationDrafts } from '@/components/chat/ConversationDrafts';

/** Keep transfers and unsent drafts alive while navigating between app pages. */
export function WorkspaceProviders({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const inWorkspace = /^\/(chat|files|search|devices|authorize|settings|login|register)(\/|$)/.test(pathname);
  // Keep an opened workspace alive while reading help or visiting the website.
  // A visitor who only opens the website does not start a device session.
  const [opened, setOpened] = useState(inWorkspace);
  if (inWorkspace && !opened) setOpened(true);
  if (!inWorkspace && !opened) return children;
  return <RealtimeProvider><ChatProvider><ConversationDrafts>{children}</ConversationDrafts></ChatProvider></RealtimeProvider>;
}
