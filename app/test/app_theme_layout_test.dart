import 'package:app/ui/app_ui.dart';
import 'package:app/color_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('action buttons have finite width inside a horizontal layout', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(colorTheme: AppColorTheme.presets.first, brightness: Brightness.light),
      home: Scaffold(body: Row(children: [
        FilledButton(onPressed: () {}, child: const Text('发送')),
        OutlinedButton(onPressed: () {}, child: const Text('添加设备')),
      ])),
    ));
    expect(tester.takeException(), isNull);
  });
}
