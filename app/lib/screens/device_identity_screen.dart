import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../device_id.dart';
import '../services/device_identity_store.dart';
import '../ui/app_ui.dart';
import '../ui/product_scaffold.dart';

class DeviceIdentityScreen extends StatefulWidget {
  const DeviceIdentityScreen({super.key, this.store});
  final DeviceIdentityStore? store;

  @override
  State<DeviceIdentityScreen> createState() => _DeviceIdentityScreenState();
}

class _DeviceIdentityScreenState extends State<DeviceIdentityScreen> {
  late final Future<DeviceIdentityStore> _store;
  String? _id;
  String? _message;
  bool _busy = false;
  bool get _zh => Localizations.localeOf(context).languageCode == 'zh';
  String txt(String zh, String en) => _zh ? zh : en;

  @override
  void initState() {
    super.initState();
    _store = widget.store != null ? Future.value(widget.store!) : getDeviceIdentityStore();
    _store.then((store) => store.getId()).then((id) {
      if (mounted) setState(() => _id = id);
    }).catchError((Object _) { /* Recovery remains available if the vault is locked. */ });
  }

  String _error(Object error) {
    final code = error is DeviceIdentityException ? error.code : '';
    return switch (code) {
      'different_app' => txt('备份属于其他应用版本或部署环境。请使用原来的版本恢复。', 'This backup belongs to a different app or deployment. Use the original app.'),
      'different_device' => txt('这份备份不属于本机，不能用来复制另一台设备的身份。', 'This backup belongs to another device.'),
      'invalid_backup' => txt('备份文件不完整或格式不正确。', 'The backup is incomplete or invalid.'),
      'storage_unavailable' => txt('无法访问系统安全存储。请解锁设备后重试。原有身份未被替换。', 'Unlock your device and try again. The existing identity has not been replaced.'),
      'recovery_required' => txt('请先恢复原有身份，再创建新的备份。', 'Restore the original identity before creating a backup.'),
      _ => txt('操作未完成，请重试。', 'The operation could not be completed. Try again.'),
    };
  }

  Future<void> _act(Future<void> Function() action) async {
    setState(() { _busy = true; _message = null; });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _message = _error(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() => _act(() async {
    final backup = await (await _store).exportBackup();
    final path = await FilePicker.platform.saveFile(
      dialogTitle: txt('保存设备身份备份', 'Save device identity'),
      fileName: 'shrimpsend-device-identity.txt',
      type: FileType.custom,
      allowedExtensions: const ['txt'],
      bytes: Uint8List.fromList(utf8.encode(backup)),
    );
    if (path != null && mounted) {
      setState(() => _message = txt('备份已保存。重装后在此页面导入即可恢复设备身份。', 'Backup saved. Import it here after reinstalling.'));
    }
  });

  Future<void> _import() => _act(() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
    if (picked == null) return;
    final file = picked.files.single;
    if (file.size > 8192) throw const DeviceIdentityException('invalid_backup');
    final bytes = file.bytes ?? (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null) throw const DeviceIdentityException('invalid_backup');
    final text = utf8.decode(bytes, allowMalformed: false);
    final store = await _store;
    final identity = await store.inspectBackup(text);
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(txt('恢复本机身份', 'Restore this device')),
        content: Text(txt(
          '将恢复备份中的设备编号和连接凭证。配对关系与设备授权仍属于原设备。\n\n请先完成当前传输；恢复后需要退出并重新打开应用。',
          'Restore the saved device ID and credential, retaining its server pairings and authorization.\n\nFinish current transfers first. Quit and reopen the app after restoring.',
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(txt('取消', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(txt('恢复身份', 'Restore'))),
        ],
      ),
    );
    if (confirmed != true) return;
    await store.restoreBackup(text);
    if (mounted) setState(() {
      _id = store.wireId(identity);
      _message = txt('身份已恢复。请退出并重新打开应用，使所有连接使用恢复后的身份。', 'Identity restored. Quit and reopen the app to use it for all connections.');
    });
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return ProductScaffold(
      preferencesTab: 'general',
      appBar: AppBar(title: Text(txt('设备身份', 'Device identity'))),
      body: FutureBuilder<DeviceIdentityStore>(
        future: _store,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(child: snapshot.hasError
                ? Text(txt('无法读取设备信息，请重新打开应用。', 'Unable to read device information. Reopen the app.'))
                : const CircularProgressIndicator());
          }
          return ValueListenableBuilder<DeviceIdentityStatus>(
            valueListenable: snapshot.data!.status,
            builder: (context, status, _) {
              final pending = status == DeviceIdentityStatus.restartRequired;
              final recovery = status == DeviceIdentityStatus.recoveryRequired;
              return ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(LucideIcons.fingerprint, size: 32, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(height: 20),
                        Text(txt('一台设备，一个身份', 'One device, one identity'), style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 12),
                        Text(txt('设备名称可以修改，身份保持不变。身份与购买账号独立，用于保留本机的配对关系和服务授权。', 'Renaming does not change your identity. It is independent of your purchasing account and preserves device pairings and authorization.'), style: TextStyle(color: colors.textSecondary, height: 1.7)),
                        const SizedBox(height: 24),
                        Text(txt('本机设备编号', 'Device ID'), style: Theme.of(context).textTheme.labelLarge),
                        const SizedBox(height: 8),
                        SelectableText(_id ?? '…', style: TextStyle(fontSize: 12, color: colors.textSecondary)),
                        const SizedBox(height: 28),
                        if (recovery || pending || status == DeviceIdentityStatus.storageUnavailable) ...[
                          Text(pending
                              ? txt('恢复已保存，请退出并重新打开应用。', 'Restore saved. Quit and reopen the app.')
                              : recovery
                              ? txt('连接凭证与原设备不一致，请导入此前保存的身份备份。', 'The credential does not match this device. Import its original identity backup.')
                              : txt('系统安全存储暂不可用。解锁设备后重试，或导入身份备份。', 'Unlock the device to access its secure storage, or import an identity backup.'),
                            style: TextStyle(color: Theme.of(context).colorScheme.error, height: 1.7)),
                          const SizedBox(height: 20),
                        ],
                        Text(txt('重装前，保存一份身份备份', 'Save an identity backup before reinstalling'), style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 10),
                        Text(txt('卸载或清除应用数据可能移除连接凭证，安卓尤其如此。系统能保留凭证时会自动恢复；否则需要导入备份。备份只包含本机身份，不包含文件和聊天记录。', 'Uninstalling or clearing app data can remove credentials, especially on Android. When the system retains them, identity restores automatically; otherwise import a backup. Files and chat history are not included.'), style: TextStyle(color: colors.textSecondary, height: 1.7)),
                        const SizedBox(height: 12),
                        Text(txt('备份包含私密连接凭证，请保存在自己的安全位置，不要发送给其他人。它与六位设备授权码不同。', 'The backup contains a private credential. Keep it safe and do not share it. It is separate from the six-character authorization code.'), style: TextStyle(color: colors.textSecondary, fontSize: 12, height: 1.7)),
                        const SizedBox(height: 24),
                        Wrap(spacing: 12, runSpacing: 12, children: [
                          FilledButton.icon(onPressed: _busy || pending || recovery ? null : _export, icon: const Icon(LucideIcons.download, size: 18), label: Text(txt('保存身份备份', 'Save backup'))),
                          OutlinedButton.icon(onPressed: _busy || pending ? null : _import, icon: const Icon(LucideIcons.upload, size: 18), label: Text(txt('从备份恢复', 'Restore backup'))),
                        ]),
                        if (_busy) const Padding(padding: EdgeInsets.only(top: 20), child: LinearProgressIndicator()),
                        if (_message != null) Padding(padding: const EdgeInsets.only(top: 20), child: Text(_message!, style: const TextStyle(height: 1.7))),
                      ]),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
