import 'package:app/device_id.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('parallel startup consumers share one installation identity and secret', () async {
    SharedPreferences.setMockInitialValues({});
    final ids = await Future.wait(List.generate(20, (_) => getOrCreateDeviceId()));
    final secrets = await Future.wait(List.generate(20, (_) => getOrCreateDeviceSecret()));
    expect(ids.toSet(), hasLength(1));
    expect(secrets.toSet(), hasLength(1));
    expect(ids.first, contains('_uuid_'));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ultrasend_device_id'), ids.first);
    expect(prefs.getString('ultrasend_device_secret'), secrets.first);
  });
}
