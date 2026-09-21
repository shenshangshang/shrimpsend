import 'package:app/color_theme.dart';
import 'package:app/ui/app_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:app/api/device_licenses.dart';
import 'package:app/screens/device_authorization_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeLicenseApi extends DeviceLicenseApi {
  Map<String, dynamic> state = {
    'status': 'FREE',
    'authorized': false,
    'pendingRequest': null,
  };
  String? submitted;
  bool fail = false;
  @override
  Future<Map<String, dynamic>> mine() async => state;
  @override
  Future<Map<String, dynamic>> redeem(String input) async {
    submitted = input;
    if (fail) throw Exception('license_invalid_code');
    state = {
      'status': 'FREE',
      'authorized': false,
      'pendingRequest': {'id': 'request'},
    };
    return state;
  }

  @override
  Future<void> release() async {
    state = {'status': 'REVOKED', 'authorized': false, 'pendingRequest': null};
  }
}

class DelayedLicenseApi extends FakeLicenseApi {
  final firstRead = Completer<Map<String, dynamic>>();
  int reads = 0;
  @override
  Future<Map<String, dynamic>> mine() =>
      ++reads == 1 ? firstRead.future : super.mine();
}

void main() {
  setUp(() { SharedPreferences.setMockInitialValues({}); });
  test(
    'QR parser accepts only high entropy HTTP fragment tokens and tolerates invalid input',
    () {
      final token = List.filled(43, 'A').join();
      expect(
        licenseQrToken('https://example.test/authorize#license=$token'),
        token,
      );
      expect(
        licenseQrToken('https://example.test/authorize?license=$token'),
        isNull,
      );
      expect(licenseQrToken('javascript:bad#license=$token'), isNull);
      expect(licenseQrToken('https://example.test/#license=%XX'), isNull);
      expect(licenseQrToken('ABC 234'), isNull);
      expect(licenseQrToken('https://example.test/#license=SHORT'), isNull);
    },
  );
  Future<void> mount(WidgetTester tester, FakeLicenseApi api) async {
    tester.view.physicalSize = const Size(1100, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: buildAppTheme(colorTheme: AppColorTheme.emerald, brightness: Brightness.light), home: DeviceAuthorizationScreen(api: api)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'guest enters code, waits for owner, sees authorization without login',
    (tester) async {
      final api = FakeLicenseApi();
      await mount(tester, api);
      expect(
        find.text('Free device · Offline transfers available'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextField), 'abc234');
      await tester.tap(find.text('Authorize this device'));
      await tester.pumpAndSettle();
      expect(api.submitted, 'ABC234');
      expect(find.text('Waiting for purchaser approval'), findsOneWidget);
      api.state = {
        'status': 'AUTHORIZED',
        'authorized': true,
        'pendingRequest': null,
        'ownerLabel': '••••0001',
      };
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(
        find.text('Authorized · Unlimited normal signaling'),
        findsOneWidget,
      );
      expect(find.text('My device slots'), findsNothing);
      await tester.tap(find.text('Release this device'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(api.state['authorized'], true);
      await tester.tap(find.text('Release this device'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(api.state['authorized'], false);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('a delayed pre-activation refresh cannot undo a new claim', (
    tester,
  ) async {
    final api = DelayedLicenseApi();
    await mount(tester, api);
    await tester.enterText(find.byType(TextField), 'ABC234');
    await tester.tap(find.text('Authorize this device'));
    await tester.pumpAndSettle();
    expect(find.text('Waiting for purchaser approval'), findsOneWidget);
    api.firstRead.complete({'status': 'FREE', 'authorized': false});
    await tester.pumpAndSettle();
    expect(find.text('Waiting for purchaser approval'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'invalid activation keeps code editable and gives recovery message',
    (tester) async {
      final api = FakeLicenseApi()..fail = true;
      await mount(tester, api);
      await tester.enterText(find.byType(TextField), 'BAD234');
      await tester.tap(find.text('Authorize this device'));
      await tester.pumpAndSettle();
      expect(
        find.text('The code is invalid, used or expired.'),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsOneWidget);
      expect(api.state['authorized'], false);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
