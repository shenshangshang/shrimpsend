import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../legal/open_source_urls.dart';
import '../ui/app_ui.dart';
import '../ui/product_scaffold.dart';

class ProductFeedbackScreen extends StatefulWidget {
  const ProductFeedbackScreen({super.key});
  @override
  State<ProductFeedbackScreen> createState() => _ProductFeedbackScreenState();
}

class _ProductFeedbackScreenState extends State<ProductFeedbackScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  String _category = 'problem';
  bool _busy = false;
  String? _error;
  bool get zh => Localizations.localeOf(context).languageCode == 'zh';
  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final title = _title.text.trim();
      final body = _body.text.trim();
      final uri = Uri.parse('$kOpenSourceRepoUrl/issues/new').replace(
        queryParameters: {
          'title': title,
          'body':
              '${_category == 'problem' ? 'Problem' : 'Suggestion'}\n\n$body',
        },
      );
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted)
        setState(
          () => _error = zh
              ? '无法打开浏览器，请复制内容后在开源仓库提交。'
              : 'Unable to open the browser. Copy your feedback and submit it in the source repository.',
        );
    } catch (_) {
      if (mounted)
        setState(
          () => _error = zh
              ? '暂时无法打开反馈草稿，请重试。'
              : 'Unable to open the draft. Please retry.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('product.feedbackDraft.title', _title.text);
    await prefs.setString('product.feedbackDraft.body', _body.text);
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(zh ? '草稿已保存在本机' : 'Draft saved on this device')),
      );
  }

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      _title.text = prefs.getString('product.feedbackDraft.title') ?? '';
      _body.text = prefs.getString('product.feedbackDraft.body') ?? '';
    });
  }

  @override
  Widget build(BuildContext context) => ProductScaffold(
    settingsLocation: '/settings/help',
    appBar: AppBar(title: Text(zh ? '问题反馈' : 'Feedback')),
    body: Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                zh ? '告诉我们发生了什么' : 'Tell us what happened',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 10),
              Text(
                zh
                    ? '描述操作过程、预期结果和实际情况，帮助我们更快定位问题。'
                    : 'Describe your steps, expected result and what happened.',
                style: TextStyle(
                  color: context.appColors.textSecondary,
                  fontSize: 14,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 8,
                children: [
                  for (final (value, label) in [
                    ('problem', zh ? '使用问题' : 'Problem'),
                    ('suggestion', zh ? '功能建议' : 'Suggestion'),
                  ])
                    ChoiceChip(
                      selected: _category == value,
                      label: Text(label),
                      onSelected: (_) => setState(() => _category = value),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _title,
                maxLength: 120,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: zh ? '标题' : 'Title',
                  hintText: zh ? '用一句话描述问题' : 'A short summary',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _body,
                minLines: 7,
                maxLines: 12,
                maxLength: 6000,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  alignLabelWithHint: true,
                  labelText: zh ? '详细描述' : 'Description',
                  hintText: zh
                      ? '操作步骤、设备和网络环境…'
                      : 'Steps, devices and network…',
                ),
              ),
              const SizedBox(height: 16),
              Text(
                zh
                    ? '将打开 GitHub 反馈草稿，由你检查后提交。可以在草稿页添加截图；请勿附带密码、授权链接或私人文件。离线时可先保存草稿。'
                    : 'A GitHub draft opens for you to review and submit. Add screenshots there. Omit passwords, authorization links and private files. You can save a draft offline.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.7,
                  color: context.appColors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _error!,
                    style: TextStyle(color: context.appColors.danger),
                  ),
                ),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton(
                    onPressed:
                        _busy ||
                            _title.text.trim().isEmpty ||
                            _body.text.trim().isEmpty
                        ? null
                        : _open,
                    child: Text(zh ? '打开反馈草稿' : 'Open feedback draft'),
                  ),
                  OutlinedButton(
                    onPressed: _save,
                    child: Text(zh ? '保存到本机' : 'Save draft'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
