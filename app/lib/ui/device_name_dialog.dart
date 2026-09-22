import 'package:flutter/material.dart';

/// Owns its controller until the dialog's closing animation has finished.
class DeviceNameDialog extends StatefulWidget {
  const DeviceNameDialog({
    super.key,
    required this.initialName,
    this.localNickname = false,
  });
  final String initialName;
  final bool localNickname;
  @override
  State<DeviceNameDialog> createState() => _DeviceNameDialogState();
}

class _DeviceNameDialogState extends State<DeviceNameDialog> {
  late final _controller = TextEditingController(text: widget.initialName);
  bool get _valid {
    final name = _controller.text.trim();
    return (widget.localNickname || name.isNotEmpty) &&
        name.length <= 80 &&
        !RegExp(r'[\x00-\x1f\x7f-\x9f]').hasMatch(name);
  }

  void _save() {
    if (_valid) Navigator.pop(context, _controller.text.trim());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final zh = Localizations.localeOf(context).languageCode == 'zh';
    return AlertDialog(
      title: Text(
        widget.localNickname
            ? (zh ? '设备备注（仅本机可见）' : 'Device nickname (local only)')
            : (zh ? '设备名称' : 'Device name'),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 80,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _save(),
        decoration: InputDecoration(
          labelText: zh ? '名称' : 'Name',
          helperText: widget.localNickname
              ? (zh ? '留空使用设备名称' : 'Leave blank to use device name')
              : (zh ? '其他设备会看到这个名称' : 'Other devices will see this name'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(zh ? '取消' : 'Cancel'),
        ),
        FilledButton(
          onPressed:
              _valid && _controller.text.trim() != widget.initialName.trim()
              ? _save
              : null,
          child: Text(zh ? '保存' : 'Save'),
        ),
      ],
    );
  }
}
