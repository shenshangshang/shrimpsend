'use client';
export function CodeInput({ id, value, onChange, label }: { id: string; value: string; onChange: (value:string)=>void; label:string }) {
  return <div className="group relative">
    <input id={id} aria-label={label} value={value} onChange={e=>onChange(e.target.value.replace(/[^a-z0-9]/gi,'').toUpperCase().slice(0,6))} autoComplete="off" autoCapitalize="characters" spellCheck={false} maxLength={12} className="absolute inset-0 z-10 h-full w-full cursor-text opacity-0"/>
    <div aria-hidden="true" className="grid grid-cols-6 gap-2 rounded-lg group-focus-within:outline-2 group-focus-within:outline-offset-4 group-focus-within:outline-ring">{Array.from({length:6},(_,i)=><span key={i} className={`flex h-14 items-center justify-center rounded-lg border bg-card font-mono text-xl ${i===value.length?'border-primary':'border-input'}`}>{value[i] || <span className="text-muted-foreground/30">−</span>}</span>)}</div>
  </div>;
}
