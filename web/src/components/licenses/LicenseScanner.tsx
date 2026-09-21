'use client';
import { useEffect, useRef, useState } from 'react';
import jsQR from 'jsqr';
import { Button } from '@/components/ui/button';

export function LicenseScanner({ onRead, zh }: { onRead: (value: string) => void; zh: boolean }) {
  const video = useRef<HTMLVideoElement>(null);
  const stream = useRef<MediaStream | null>(null);
  const animation = useRef<number>(0);
  const [error, setError] = useState('');
  const [running, setRunning] = useState(false);
  const alive = useRef(true);
  const stop = () => {
    stream.current?.getTracks().forEach(track => track.stop());
    stream.current = null;
    cancelAnimationFrame(animation.current);
  };
  useEffect(() => { alive.current = true; return () => { alive.current = false; stop(); }; }, []);
  const decode = (source: CanvasImageSource, width: number, height: number) => {
    const canvas = document.createElement('canvas');
    const scale = Math.min(1, 960 / width);
    canvas.width = Math.round(width * scale); canvas.height = Math.round(height * scale);
    const context = canvas.getContext('2d', { willReadFrequently: true })!;
    context.drawImage(source, 0, 0, canvas.width, canvas.height);
    const pixels = context.getImageData(0, 0, canvas.width, canvas.height);
    return jsQR(pixels.data, pixels.width, pixels.height)?.data;
  };
  const start = async () => {
    stop(); setError('');
    try {
      const next = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' }, audio: false });
      if (!alive.current) { next.getTracks().forEach(track => track.stop()); return; }
      stream.current = next; setRunning(true);
      if (video.current) { video.current.srcObject = next; await video.current.play(); }
      let last = 0;
      const read = (now: number) => {
        if (!stream.current) return;
        const v = video.current;
        if (v && v.videoWidth && now - last > 200) {
          last = now;
          const value = decode(v, v.videoWidth, v.videoHeight);
          if (value) { stop(); setRunning(false); onRead(value); return; }
        }
        animation.current = requestAnimationFrame(read);
      };
      animation.current = requestAnimationFrame(read);
    } catch {
      stop(); setRunning(false);
      setError(zh ? '无法使用摄像头，可以选择二维码图片或输入授权码。' : 'Camera unavailable. Choose a QR image or enter your code.');
    }
  };
  return <div className="space-y-3">
    <div className="flex flex-wrap gap-2">
      <Button variant="outline" type="button" onClick={() => running ? (stop(), setRunning(false)) : void start()}>{running ? (zh ? '停止扫码' : 'Stop camera') : (zh ? '扫码授权' : 'Scan QR code')}</Button>
      <label className="inline-flex cursor-pointer items-center rounded-md border px-3 py-2 text-sm">
        {zh ? '识别二维码图片' : 'Choose QR image'}
        <input className="sr-only" type="file" accept="image/*" aria-label={zh ? '选择授权二维码图片' : 'Select authorization QR image'} onChange={async event => {
          const file = event.target.files?.[0]; event.target.value = ''; if (!file) return;
          stop(); setRunning(false); setError('');
          try {
            const bitmap = await createImageBitmap(file);
            const value = decode(bitmap, bitmap.width, bitmap.height); bitmap.close();
            if (!value) throw new Error('no code');
            onRead(value);
          } catch { setError(zh ? '未识别到二维码，请换一张清晰图片。' : 'No QR code found. Choose a clearer image.'); }
        }} />
      </label>
    </div>
    <video ref={video} muted playsInline className={running ? 'max-h-64 w-full rounded-xl bg-black' : 'hidden'} />
    {error && <p role="alert" className="text-sm text-muted-foreground">{error}</p>}
  </div>;
}
