import '../ui/app_ui.dart';
import '../ui/product_code_input.dart';
import '../device_id.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../ui/product_scaffold.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../api/device_licenses.dart';
import '../config/env.dart';
import '../providers/auth_provider.dart';
import 'qr_scanner_screen.dart';

class DeviceAuthorizationScreen extends ConsumerStatefulWidget {
  final DeviceLicenseApi? api;
  final bool ownerOnly;
  final bool embedded;
  const DeviceAuthorizationScreen({
    super.key,
    this.api,
    this.ownerOnly = false,
    this.embedded = false,
  });
  @override
  ConsumerState<DeviceAuthorizationScreen> createState() =>
      _DeviceAuthorizationScreenState();
}

class _DeviceAuthorizationScreenState
    extends ConsumerState<DeviceAuthorizationScreen> {
  late final DeviceLicenseApi api;
  final input = TextEditingController();
  Timer? timer;
  Map<String, dynamic>? mine, dashboard, issued;
  String? error;
  bool busy = false;
  String deviceName = '';
  int refreshRevision = 0;
  bool get zh => Localizations.localeOf(context).languageCode == 'zh';
  String txt(String cn, String en) => zh ? cn : en;
  @override
  void initState() {
    super.initState();
    api = widget.api ?? DeviceLicenseApi();
    getDeviceName()
        .then((name) {
          if (mounted) setState(() => deviceName = name);
        })
        .catchError((_) {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!busy) refresh();
    });
    timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!busy) refresh();
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    input.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    if (!mounted) return;
    final current = ++refreshRevision;
    try {
      final device = await api.mine();
      final owner = ref.read(authProvider).isLoggedIn
          ? await api.dashboard()
          : null;
      if (!mounted || current != refreshRevision) return;
      setState(() {
        mine = device;
        dashboard = owner;
        if (issued != null &&
            !(owner?['requests'] as List? ?? []).any(
              (r) => r['id'] == issued!['id'],
            )) {
          issued = null;
        }
      });
    } catch (e) {
      if (mounted && current == refreshRevision) {
        setState(() => error = deviceLicenseError(e, zh));
      }
    }
  }

  Future<void> act(Future<void> Function() work) async {
    refreshRevision++;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await work();
      await refresh();
    } catch (e) {
      if (mounted) setState(() => error = deviceLicenseError(e, zh));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(txt('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(txt('确认', 'Confirm')),
            ),
          ],
        ),
      ) ??
      false;
  String link(Map<String, dynamic> value) =>
      '${Env.webUrl}/authorize#license=${Uri.encodeComponent(value['qrToken'] as String)}';
  Widget box(List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final authorized = mine?['authorized'] == true;
    final pending = mine?['pendingRequest'] != null;
    final colors = context.appColors;
    final content = ListView(
      padding: const EdgeInsets.all(28),
      children: widget.ownerOnly
          ? _ownerContent()
          : [
              Text(
                txt(
                  '授权本机即可享受会员信令服务，无需登录购买账号。',
                  'Authorize this device for member signaling without signing in to the purchasing account.',
                ),
                style: TextStyle(
                  fontSize: 14,
                  color: colors.textSecondary,
                  height: 1.7,
                ),
              ),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  border: Border.symmetric(
                    horizontal: BorderSide(color: colors.border),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      LucideIcons.monitor,
                      size: 32,
                      color: colors.textSecondary,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            deviceName.isEmpty
                                ? txt('本机', 'This device')
                                : deviceName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            authorized
                                ? txt(
                                    '已授权 · 正常使用不限信令次数',
                                    'Authorized · Unlimited normal signaling',
                                  )
                                : pending
                                ? txt(
                                    '等待购买端确认',
                                    'Waiting for purchaser approval',
                                  )
                                : mine?['status'] == 'SUSPENDED'
                                ? txt(
                                    '名额暂不可用，请联系购买者',
                                    'Slot unavailable. Contact the purchaser.',
                                  )
                                : mine?['status'] == 'EXPIRED'
                                ? txt('授权已到期', 'Authorization expired')
                                : txt(
                                    '免费设备 · 支持离线传输',
                                    'Free device · Offline transfers available',
                                  ),
                            style: TextStyle(
                              fontSize: 13,
                              color: authorized
                                  ? Theme.of(context).colorScheme.primary
                                  : colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              if (pending) ...[
                Icon(
                  LucideIcons.clock3,
                  color: Theme.of(context).colorScheme.primary,
                  size: 32,
                ),
                const SizedBox(height: 16),
                Text(
                  txt(
                    '请在购买端确认这台设备',
                    'Confirm this device on the purchasing account',
                  ),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  txt(
                    '打开「会员与名额 → 设备名额」，核对设备后确认。本页会自动更新。',
                    'Open Membership & slots → Device slots and approve this device. This page updates automatically.',
                  ),
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.7,
                    color: colors.textSecondary,
                  ),
                ),
              ] else if (!authorized) ...[
                Text(
                  txt('输入六位授权码', 'Enter the six-character code'),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 390),
                    child: ProductCodeInput(
                      controller: input,
                      label: txt('授权码', 'Authorization code'),
                      enabled: !busy,
                      onSubmitted: (_) => _redeemCode(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  txt(
                    '授权码由购买者生成。输入后，需要购买者确认设备。',
                    'Ask the purchaser to generate a code, then approve your device.',
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary,
                    height: 1.7,
                  ),
                ),
                const SizedBox(height: 22),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton(
                      onPressed: busy ? null : _redeemCode,
                      child: Text(
                        busy
                            ? txt('正在授权…', 'Authorizing…')
                            : txt('授权本机', 'Authorize this device'),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy ? null : _scanCode,
                      icon: const Icon(LucideIcons.scanLine, size: 17),
                      label: Text(txt('扫码授权', 'Scan QR code')),
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  children: [
                    Icon(
                      LucideIcons.circleCheck,
                      color: Theme.of(context).colorScheme.primary,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      txt('本机已获得授权', 'This device is authorized'),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (mine?['ownerLabel'] != null)
                  Text(
                    '${txt('授权来源', 'Provided by')}  ${mine!['ownerLabel']}',
                    style: const TextStyle(fontSize: 14),
                  ),
                const SizedBox(height: 12),
                Text(
                  '${txt('有效期', 'Valid until')}  ${mine?['expiresAt'] ?? txt('长期有效', 'Lifetime')}',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    onPressed: () => openProductRoute(context, '/'),
                    child: Text(txt('开始传输', 'Start transferring')),
                  ),
                ),
              ],
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      error!,
                      style: TextStyle(fontSize: 13, color: colors.danger),
                    ),
                  ),
                ),
              if (mine != null &&
                  [
                    'AUTHORIZED',
                    'EXPIRED',
                    'SUSPENDED',
                  ].contains(mine!['status'])) ...[
                const SizedBox(height: 28),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: busy
                        ? null
                        : () async {
                            if (await confirm(
                                  txt('解除本机授权？', 'Release authorization?'),
                                  txt(
                                    '恢复免费服务，已下载文件会保留。',
                                    'Return to free service. Downloaded files are kept.',
                                  ),
                                ) &&
                                mounted)
                              await act(api.release);
                          },
                    child: Text(txt('解除本机授权', 'Release this device')),
                  ),
                ),
              ],
              const SizedBox(height: 36),
              const Divider(),
              const SizedBox(height: 14),
              Text(
                txt(
                  '文件与会话属于设备。授权不会同步账号文件或传输历史。',
                  'Files and conversations belong to this device. Authorization does not sync account files or history.',
                ),
                style: TextStyle(
                  fontSize: 12,
                  height: 1.8,
                  color: colors.textSecondary,
                ),
              ),
              if (!authorized && !pending)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () =>
                        openProductRoute(context, '/settings/membership'),
                    child: Text(
                      txt('购买或管理设备名额', 'Purchase or manage device slots'),
                    ),
                  ),
                ),
            ],
    );
    if (widget.embedded) return content;
    return ProductScaffold(
      settingsLocation: widget.ownerOnly
          ? '/settings/membership'
          : '/authorize',
      appBar: AppBar(
        title: Text(
          widget.ownerOnly
              ? txt('设备名额', 'Device slots')
              : txt('本机授权', 'Device authorization'),
        ),
      ),
      body: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: content,
        ),
      ),
    );
  }

  Future<void> _redeemCode() async {
    if (busy) return;
    if (!RegExp(r'^[A-Z0-9]{6}$').hasMatch(input.text)) {
      setState(
        () => error = txt('请输入六位大写字母或数字', 'Enter six letters or numbers'),
      );
      return;
    }
    await act(() async {
      await api.redeem(input.text);
      input.clear();
    });
  }

  Future<void> _scanCode() async {
    final value = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => const QrScannerScreen(licenseOnly: true),
      ),
    );
    if (value == null || !mounted) return;
    if (licenseQrToken(value) == null) {
      setState(
        () => error = txt(
          '这不是设备授权二维码',
          'This is not a device authorization QR code',
        ),
      );
      return;
    }
    if (await confirm(
          txt('为本机添加授权？', 'Authorize this device?'),
          txt(
            '确认使用此二维码中的名额授权本机。',
            'Use the device slot represented by this QR code.',
          ),
        ) &&
        mounted)
      await act(() async {
        await api.redeem(value);
      });
  }

  List<Widget> _ownerContent() {
    final authorized = mine?['authorized'] == true;
    return [
      if (error != null)
        Text(
          error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      if (ref.watch(authProvider).isLoggedIn) ...[
        const SizedBox(height: 20),
        Text(
          txt('我的设备名额', 'My device slots'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        box([
          Text(
            dashboard == null
                ? '—'
                : '${dashboard!['used']} / ${dashboard!['capacity']}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          Text(
            txt(
              '已授权设备 · 管理账号登录不占名额',
              'Authorized devices · Billing sign-in does not use a slot',
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: busy || (dashboard?['available'] as num? ?? 0) <= 0
                    ? null
                    : () => act(() async {
                        final value = await api.issue();
                        if (mounted) setState(() => issued = value);
                      }),
                child: Text(txt('生成授权码', 'Generate code')),
              ),
              OutlinedButton(
                onPressed:
                    busy ||
                        authorized ||
                        (dashboard?['available'] as num? ?? 0) <= 0
                    ? null
                    : () => act(() async {
                        final value = await api.issue();
                        try {
                          await api.redeem(link(value));
                        } catch (e) {
                          await api.cancel(value['id']);
                          rethrow;
                        }
                      }),
                child: Text(txt('使用名额授权本机', 'Use a slot for this device')),
              ),
            ],
          ),
          if (issued != null) ...[
            const SizedBox(height: 20),
            Wrap(
              spacing: 20,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(10),
                  child: QrImageView(data: link(issued!), size: 150),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      issued!['code'] as String,
                      style: Theme.of(
                        context,
                      ).textTheme.headlineMedium?.copyWith(letterSpacing: 5),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      txt(
                        '10 分钟内使用，手输需确认',
                        'Use within 10 minutes. Manual entry needs approval.',
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: link(issued!))),
                      child: Text(txt('复制授权链接', 'Copy authorization link')),
                    ),
                  ],
                ),
              ],
            ),
          ],
          for (final r in dashboard?['requests'] as List? ?? []) ...[
            const Divider(height: 32),
            Text(
              r['status'] == 'CLAIMED'
                  ? '${txt('请求授权', 'Request')}: ${r['name']}'
                  : txt('授权码待使用', 'Code waiting for a device'),
            ),
            if (r['deviceId'] != null)
              SelectableText(
                '${r['platform']} · ${r['deviceId']}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            Wrap(
              spacing: 8,
              children: [
                if (r['status'] == 'CLAIMED')
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () => act(() async {
                            await api.approve(r['id']);
                          }),
                    child: Text(txt('确认授权', 'Approve device')),
                  ),
                TextButton(
                  onPressed: busy ? null : () => act(() => api.cancel(r['id'])),
                  child: Text(txt('撤销', 'Cancel')),
                ),
              ],
            ),
          ],
          for (final d in dashboard?['devices'] as List? ?? []) ...[
            const Divider(height: 32),
            Text(
              '${d['name']} · ${d['authorized'] == true ? txt('已授权', 'Authorized') : txt('暂停权益', 'Inactive')}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            SelectableText(
              '${d['platform']} · ${d['deviceId']}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          final controller = TextEditingController(
                            text: d['name'],
                          );
                          final value = await showDialog<String>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text(txt('设备备注', 'Device name')),
                              content: TextField(
                                controller: controller,
                                maxLength: 128,
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: Text(txt('取消', 'Cancel')),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(
                                    ctx,
                                    controller.text.trim(),
                                  ),
                                  child: Text(txt('保存', 'Save')),
                                ),
                              ],
                            ),
                          );
                          controller.dispose();
                          if (value != null && value.isNotEmpty && mounted) {
                            await act(() => api.rename(d['deviceId'], value));
                          }
                        },
                  child: Text(txt('备注', 'Rename')),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          if (await confirm(
                                txt('解除设备授权？', 'Release this device?'),
                                txt(
                                  '名额可重新分配，设备上的文件会保留。',
                                  'The slot becomes available. Device files are kept.',
                                ),
                              ) &&
                              mounted) {
                            await act(() => api.revoke(d['deviceId']));
                          }
                        },
                  child: Text(txt('解除授权', 'Release slot')),
                ),
              ],
            ),
          ],
        ]),
        TextButton(
          onPressed: () => openProductRoute(context, '/settings/membership'),
          child: Text(txt('购买或续费设备服务包', 'Purchase or renew a device plan')),
        ),
      ] else
        TextButton(
          onPressed: () async {
            await Navigator.pushNamed(context, '/login');
            if (mounted) await refresh();
          },
          child: Text(txt('登录购买或管理名额', 'Sign in to purchase or manage slots')),
        ),
    ];
  }
}
