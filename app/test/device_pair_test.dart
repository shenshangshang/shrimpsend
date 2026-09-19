import 'package:flutter_test/flutter_test.dart';
import 'package:app/device_pair.dart';

void main() {
  test('parseDevicePairUri reads ultrasend://pair/<id>', () {
    expect(
      parseDevicePairUri('ultrasend://pair/abc-123'),
      'abc-123',
    );
    expect(
      parseDevicePairUri('  ultrasend://pair/web_device?x=1  '),
      'web_device',
    );
    expect(parseDevicePairUri('ultrasend://qr-login/abc'), isNull);
    expect(parseDevicePairUri('abc-123'), isNull);
  });

  test('devicePairUri builds the pair token', () {
    expect(devicePairUri('dev-1'), 'ultrasend://pair/dev-1');
  });
}
