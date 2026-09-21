import type { ReactNode } from 'react';
import type { LucideIcon } from 'lucide-react';
import { cn } from '@/lib/utils';

export function PageHeader({ title, description, actions }: { title: string; description?: string; actions?: ReactNode }) {
  return <header className="page-heading"><div className="min-w-0"><h1>{title}</h1>{description && <p>{description}</p>}</div>{actions && <div className="page-actions">{actions}</div>}</header>;
}
export function EmptyState({ icon: Icon, title, description, action }: { icon: LucideIcon; title: string; description?: string; action?: ReactNode }) {
  return <div className="empty-state"><Icon size={36} strokeWidth={1.35} /><h2>{title}</h2>{description && <p>{description}</p>}{action}</div>;
}
export function SettingRow({ title, description, children, control, className }: { title: string; description?: string; children?: ReactNode; control?: ReactNode; className?: string }) {
  return <div className={cn('setting-row', className)}><div className="min-w-0"><div className="font-medium">{title}</div>{description && <p>{description}</p>}</div><div className="setting-control">{control ?? children}</div></div>;
}
export function Toggle({ checked, onChange, label, disabled }: { checked: boolean; onChange: (value: boolean) => void; label: string; disabled?: boolean }) {
  return <button type="button" role="switch" aria-checked={checked} aria-label={label} disabled={disabled} onClick={() => onChange(!checked)} className="setting-toggle"><span><i /></span></button>;
}
