'use client';
import { useEffect, useState } from 'react';
import { ReceiptText, RefreshCw } from 'lucide-react';
import { listMembershipOrders, type MembershipOrder } from '@/lib/api/membership';
import { useI18n } from '@/contexts/I18nContext';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';

export function OrderHistory() {
  const { localeBcp47 } = useI18n(); const zh = localeBcp47.startsWith('zh');
  const [orders, setOrders] = useState<MembershipOrder[]>([]);
  const [loading, setLoading] = useState(true); const [error, setError] = useState(false);
  const [revision, setRevision] = useState(0); const [detail, setDetail] = useState<MembershipOrder | null>(null);
  useEffect(() => { let alive = true; listMembershipOrders().then(value => { if (alive) setOrders(value); }).catch(() => { if (alive) setError(true); }).finally(() => { if (alive) setLoading(false); }); return () => { alive = false; }; }, [revision]);
  const money = (order: MembershipOrder) => new Intl.NumberFormat(localeBcp47, { style: 'currency', currency: order.currency || 'CNY' }).format(order.payableAmountCent / 100);
  const status = (value: string) => ({ CREATED: zh ? '待支付' : 'Pending', PAID: zh ? '已支付' : 'Paid', GRANTED: zh ? '已生效' : 'Active', CLOSED: zh ? '已关闭' : 'Closed', FAILED: zh ? '失败' : 'Failed', REFUNDED: zh ? '已退款' : 'Refunded' }[value] || value);
  const retry = () => { setLoading(true); setError(false); setRevision(value => value + 1); };
  return <section className="space-y-5">
    <div className="flex items-center justify-between"><div><h2 className="text-base font-medium">{zh ? '订单记录' : 'Order history'}</h2><p className="mt-1 text-xs text-muted-foreground">{zh ? '此账号最近的 100 笔订单。商店订阅也可在原购买渠道管理。' : 'The latest 100 account orders. Manage store subscriptions in the original store.'}</p></div><Button variant="ghost" size="icon" aria-label={zh ? '刷新订单' : 'Refresh orders'} disabled={loading} onClick={retry}><RefreshCw className="size-4"/></Button></div>
    {loading ? <p role="status" className="py-16 text-center text-sm text-muted-foreground">{zh ? '正在读取订单…' : 'Loading orders…'}</p> : error ? <div role="alert" className="rounded-xl border p-6"><p className="mb-3 text-sm">{zh ? '暂时无法读取订单，请稍后重试。' : 'Unable to load orders. Please retry.'}</p><Button variant="outline" onClick={retry}>{zh ? '重试' : 'Retry'}</Button></div> : orders.length === 0 ? <div className="py-20 text-center text-muted-foreground"><ReceiptText className="mx-auto mb-4 size-8"/><p className="text-sm">{zh ? '还没有订单记录' : 'No orders yet'}</p></div> : <div className="divide-y rounded-xl border px-4">{orders.map(order => <button key={order.orderNo} type="button" onClick={() => setDetail(order)} className="flex min-h-20 w-full items-center justify-between gap-4 py-4 text-left hover:bg-muted/30"><span className="min-w-0"><span className="block text-sm font-medium">{order.toTier}</span><span className="mt-1 block truncate text-xs text-muted-foreground">{new Date(order.createdAt).toLocaleDateString(localeBcp47)} · {order.orderNo}</span></span><span className="shrink-0 text-right"><span className="block text-sm tabular-nums">{money(order)}</span><span className="mt-1 block text-xs text-muted-foreground">{status(order.status)}</span></span></button>)}</div>}
    <Dialog open={!!detail} onOpenChange={open => { if (!open) setDetail(null); }}><DialogContent className="max-w-md"><DialogHeader><DialogTitle>{zh ? '订单详情' : 'Order details'}</DialogTitle></DialogHeader>{detail && <dl className="space-y-4 text-sm">{[[zh ? '订单号' : 'Order', detail.orderNo], [zh ? '会员方案' : 'Plan', detail.toTier], [zh ? '金额' : 'Amount', money(detail)], [zh ? '支付渠道' : 'Channel', detail.channel], [zh ? '状态' : 'Status', status(detail.status)], [zh ? '创建时间' : 'Created', new Date(detail.createdAt).toLocaleString(localeBcp47)]].map(([label,value]) => <div key={label} className="flex justify-between gap-6"><dt className="shrink-0 text-muted-foreground">{label}</dt><dd className="break-all text-right">{value}</dd></div>)}</dl>}</DialogContent></Dialog>
  </section>;
}
