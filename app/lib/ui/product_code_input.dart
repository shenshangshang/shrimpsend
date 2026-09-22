import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_ui.dart';

class ProductCodeInput extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final bool enabled;
  final ValueChanged<String>? onSubmitted;
  const ProductCodeInput({
    super.key,
    required this.controller,
    required this.label,
    this.enabled = true,
    this.onSubmitted,
  });
  @override
  State<ProductCodeInput> createState() => _ProductCodeInputState();
}

class _ProductCodeInputState extends State<ProductCodeInput> {
  final _focus = FocusNode();
  @override
  void initState() {
    super.initState();
    _focus.addListener(_changed);
    widget.controller.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(ProductCodeInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final text = widget.controller.text;
    return SizedBox(
      height: 56,
      child: Stack(
        children: [
          ExcludeSemantics(
            child: Row(
              children: [
                for (var i = 0; i < 6; i++)
                  Expanded(
                    child: Container(
                      margin: EdgeInsets.only(right: i == 5 ? 0 : 10),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: colors.surface,
                        border: Border.all(
                          color:
                              _focus.hasFocus &&
                                  (i == text.length ||
                                      (text.length == 6 && i == 5))
                              ? Theme.of(context).colorScheme.primary
                              : colors.border,
                          width: _focus.hasFocus && i == text.length ? 2 : 1,
                        ),
                      ),
                      child: Text(
                        i < text.length ? text[i] : '',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Positioned.fill(
            child: Opacity(
              opacity: 0,
              alwaysIncludeSemantics: true,
              child: TextField(
                controller: widget.controller,
                focusNode: _focus,
                enabled: widget.enabled,
                onSubmitted: widget.onSubmitted,
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  TextInputFormatter.withFunction((oldValue, newValue) {
                    final normalized = newValue.text.toUpperCase().replaceAll(
                      RegExp('[^A-Z0-9]'),
                      '',
                    );
                    final value = normalized.length > 6
                        ? normalized.substring(0, 6)
                        : normalized;
                    return TextEditingValue(
                      text: value,
                      selection: TextSelection.collapsed(offset: value.length),
                    );
                  }),
                ],
                decoration: InputDecoration(labelText: widget.label),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
