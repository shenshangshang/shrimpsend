'use client';
import { useRouter } from 'next/navigation';
import { useDeviceListPanelWidth } from '@/hooks/useDeviceListPanelWidth';
import { useMinWidthMd } from '@/hooks/useMediaQuery';
import { useChatContext } from '@/contexts/ChatContext';
import { ConnectionDiagnosticSheet } from '@/components/chat/ConnectionDiagnosticSheet';
import { AppNavigation } from './AppShell';
import { DeviceListPanel } from './DeviceListPanel';
import { ChatDetailPanel } from './ChatDetailPanel';

export function MainLayout() {
  const isWide = useMinWidthMd();
  const width = useDeviceListPanelWidth();
  const router = useRouter();
  const { selectedDeviceId, setSelectedDeviceId, connectionDiagnostic, diagnosticSheetOpen, setDiagnosticSheetOpen } = useChatContext();
  const inConversation = !isWide && !!selectedDeviceId;
  return <>
    <div className={`conversation-shell flex h-dvh text-foreground ${!inConversation ? 'max-md:pb-[calc(64px+env(safe-area-inset-bottom))]' : ''}`}>
      <AppNavigation hideMobile={inConversation} />
      {(isWide || !selectedDeviceId) && <div className="min-h-0 shrink-0 border-r border-border max-md:flex-1" style={isWide ? { width } : undefined}>
        <DeviceListPanel onShowSettings={() => router.push('/settings')} />
      </div>}
      {(isWide || selectedDeviceId) && <ChatDetailPanel showBackButton={!isWide} onBack={() => setSelectedDeviceId(null)} />}
    </div>
    <ConnectionDiagnosticSheet open={diagnosticSheetOpen} onOpenChange={setDiagnosticSheetOpen} state={connectionDiagnostic} />
  </>;
}
