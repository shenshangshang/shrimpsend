const PREFIX = '[Ultrasend]';
const isProd = typeof process !== 'undefined' && process.env.NODE_ENV === 'production';
export type AppLogEntry = { at: number; tag: string; level: string; message: string };
let entries: AppLogEntry[] = [];
const listeners = new Set<() => void>();
export const readAppLogs = () => entries;
export const subscribeAppLogs = (listener: () => void) => { listeners.add(listener); return () => { listeners.delete(listener); }; };
export function clearAppLogs() { entries = []; listeners.forEach(listener => listener()); }
function record(tag: string, level: string, message: string) {
  if (typeof window === 'undefined') return;
  // Arguments can contain messages, credentials and file paths. Never retain them.
  const safe = message.replace(/Bearer\s+\S+/gi, 'Bearer [redacted]').replace(/[\w.+-]+@[\w.-]+\.[a-z]{2,}/gi, '[email]').replace(/https?:\/\/\S+/gi, '[address]');
  entries = [...entries.slice(-499), { at: Date.now(), tag, level, message: safe }];
  listeners.forEach(listener => listener());
}

function format(tag: string, level: string, message: string, ...args: unknown[]): void {
  record(tag, level, message);
  const line = `${PREFIX}[${tag}] ${level}: ${message}`;
  if (args.length > 0) {
    console.log(line, ...args);
  } else {
    console.log(line);
  }
}

export const logger = {
  debug(tag: string, message: string, ...args: unknown[]): void {
    if (isProd) return;
    format(tag, 'DEBUG', message, ...args);
  },
  info(tag: string, message: string, ...args: unknown[]): void {
    format(tag, 'INFO', message, ...args);
  },
  warn(tag: string, message: string, ...args: unknown[]): void {
    record(tag, 'WARN', message);
    console.warn(`${PREFIX}[${tag}] WARN: ${message}`, ...args);
  },
  error(tag: string, message: string, ...args: unknown[]): void {
    record(tag, 'ERROR', message);
    console.error(`${PREFIX}[${tag}] ERROR: ${message}`, ...args);
  },
};
