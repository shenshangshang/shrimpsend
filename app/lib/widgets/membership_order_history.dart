import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api/membership.dart';
import '../ui/app_ui.dart';

class MembershipOrderHistory extends StatefulWidget {
  const MembershipOrderHistory({super.key});
  @override
  State<MembershipOrderHistory> createState() => _MembershipOrderHistoryState();
}

class _MembershipOrderHistoryState extends State<MembershipOrderHistory> {
  late Future<List<MembershipOrder>> _orders = listMembershipOrders();
  bool get zh => Localizations.localeOf(context).languageCode == 'zh';
  String _status(String value) =>
      {
        'CREATED': zh ? '待支付' : 'Pending',
        'PAID': zh ? '已支付' : 'Paid',
        'GRANTED': zh ? '已生效' : 'Active',
        'CLOSED': zh ? '已关闭' : 'Closed',
        'FAILED': zh ? '失败' : 'Failed',
        'REFUNDED': zh ? '已退款' : 'Refunded',
      }[value] ??
      value;
  String _amount(MembershipOrder order) =>
      '${order.currency} ${(order.payableAmountCent / 100).toStringAsFixed(2)}';
  String _date(MembershipOrder order) => order.createdAt == null
      ? '—'
      : MaterialLocalizations.of(context).formatMediumDate(
          DateTime.fromMillisecondsSinceEpoch(order.createdAt!),
        );
  void _refresh() => setState(() => _orders = listMembershipOrders());
  void _detail(MembershipOrder order) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(zh ? '订单详情' : 'Order details'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (label, value) in [
              (zh ? '订单号' : 'Order', order.orderNo),
              (zh ? '会员方案' : 'Plan', order.toTier),
              (zh ? '金额' : 'Amount', _amount(order)),
              (zh ? '支付渠道' : 'Channel', order.channel),
              (zh ? '状态' : 'Status', _status(order.status)),
              (zh ? '创建时间' : 'Created', _date(order)),
            ])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(color: context.appColors.textSecondary),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: SelectableText(value, textAlign: TextAlign.end),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: order.orderNo));
            if (context.mounted)
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(zh ? '订单号已复制' : 'Order number copied')),
              );
          },
          child: Text(zh ? '复制订单号' : 'Copy order number'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(zh ? '关闭' : 'Close'),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topLeft,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 900),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    zh ? '订单记录' : 'Order history',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  onPressed: _refresh,
                  tooltip: zh ? '刷新订单' : 'Refresh orders',
                  icon: const Icon(Icons.refresh_outlined, size: 20),
                ),
              ],
            ),
            Text(
              zh
                  ? '此账号最近的 100 笔订单。商店订阅也可在原购买渠道管理。'
                  : 'The latest 100 account orders. Manage store subscriptions in the original store.',
              style: TextStyle(
                fontSize: 12,
                color: context.appColors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: FutureBuilder<List<MembershipOrder>>(
                future: _orders,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done)
                    return const Center(child: CircularProgressIndicator());
                  if (snapshot.hasError)
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(zh ? '暂时无法读取订单' : 'Unable to load orders'),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: _refresh,
                            child: Text(zh ? '重试' : 'Retry'),
                          ),
                        ],
                      ),
                    );
                  final orders = snapshot.data ?? [];
                  if (orders.isEmpty)
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.receipt_long_outlined,
                            size: 32,
                            color: context.appColors.textSecondary,
                          ),
                          const SizedBox(height: 16),
                          Text(zh ? '还没有订单记录' : 'No orders yet'),
                        ],
                      ),
                    );
                  return ListView.separated(
                    itemCount: orders.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final order = orders[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        onTap: () => _detail(order),
                        title: Text(order.toTier),
                        subtitle: Text(
                          '${_date(order)} · ${order.orderNo}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(_amount(order)),
                            const SizedBox(height: 4),
                            Text(
                              _status(order.status),
                              style: TextStyle(
                                fontSize: 12,
                                color: context.appColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
