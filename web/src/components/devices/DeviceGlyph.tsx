import { Laptop, Monitor, Smartphone, Tablet, type LucideProps } from 'lucide-react';

/** Show the kind of device consistently across discovery and conversations. */
export function DeviceGlyph({ platform, name = '', ...props }: LucideProps & { platform?: string | null; name?: string }) {
  const kind = `${platform ?? ''} ${name}`.toLowerCase();
  const Icon = /ipad|tablet/.test(kind) ? Tablet
    : /ios|iphone|android|harmony/.test(kind) ? Smartphone
    : /windows|linux/.test(kind) ? Monitor : Laptop;
  return <Icon strokeWidth={1.6} {...props} />;
}
